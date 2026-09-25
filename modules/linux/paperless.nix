# paperless-ngx on non-NixOS Debian (maui) -- notes.txt item 1.
#
# No container. nixpkgs ships paperless-ngx, so this is the NixOS module's unit
# set (nixos/modules/services/misc/paperless.nix) ported to systemd --user
# services, the same way vaultwarden.nix ports vaultwarden: five units --
# redis, scheduler (celery beat), task queue (celery worker), consumer, web.
#
# Backend is SQLite, which is paperless' default and plenty for one person.
# Documents live under /srv/storage (the 687G spinning disk), not $HOME.
#
# Scope, deliberately: paperless is the archive of record for *admin* documents
# -- bills, letters, statements. The Obsidian vault's `_inbox/` and its own OCR
# path stay for study capture. A file lives in exactly one of the two, and a
# note that needs a document links to it by URL. See ./vault-sync.nix.
#
# Reachable at https://<this host>.<tailnet>.ts.net:8444 via `tailscale serve`;
# the FQDN is resolved at start time, never written down (./lib/tailnet.nix).
#
# Not included: gotenberg and tika, which paperless only needs to ingest office
# documents and email. Both are in nixpkgs -- add units for them and set
# PAPERLESS_TIKA_ENABLED if that day comes.
#
# First-time setup (deferred to the end of the build-out):
#   paperless-manage createsuperuser
{
  config,
  pkgs,
  lib,
  ...
}: let
  tailnet = import ./lib/tailnet.nix {inherit pkgs;};

  pkg = pkgs.paperless-ngx;

  root = "/srv/storage/paperless";
  dataDir = "${root}/data";
  mediaDir = "${root}/media";
  consumeDir = "${root}/consume";
  # paperless v3's Tantivy search backend, unlike the old Whoosh one, does not
  # create its index directory on demand: `document_index reindex` aborts with
  # ENOENT instead. The NixOS module makes it a tmpfiles rule for the same
  # reason.
  indexDir = "${dataDir}/index";

  port = 28981;
  servePort = 8444;

  # Ceiling for the classifier's OpenMP threads; see the OMP_NUM_THREADS block
  # in the runner below for why there is a ceiling at all.
  maxOmpThreads = 4;

  # Outside the store: a secret key world-readable in /nix/store would let
  # anyone on the box forge session cookies.
  secretKeyFile = "${dataDir}/secret-key.env";

  env = {
    PAPERLESS_DATA_DIR = dataDir;
    PAPERLESS_MEDIA_ROOT = mediaDir;
    PAPERLESS_CONSUMPTION_DIR = consumeDir;
    PAPERLESS_THUMBNAIL_FONT_NAME = "${pkgs.liberation_ttf}/share/fonts/truetype/LiberationSerif-Regular.ttf";

    PAPERLESS_TIME_ZONE = "Europe/London";
    PAPERLESS_OCR_LANGUAGE = "eng";

    # Leaving PAPERLESS_DBENGINE unset selects SQLite.

    # python-requests ignores the system CA bundle unless told; this is the
    # Debian path, and paperless needs it for django-allauth.
    REQUESTS_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt";

    # Model/data caches that ship with the package.
    NLTK_DATA = pkg.nltkDataDir;
    PAPERLESS_NLTK_DIR = pkg.nltkDataDir;
    TIKTOKEN_CACHE_DIR = pkg.tiktokenCacheDir;

    GRANIAN_HOST = "127.0.0.1";
    GRANIAN_PORT = toString port;
    GRANIAN_WORKERS_KILL_TIMEOUT = "60";
  };

  # Every paperless process starts through this: it assembles the environment,
  # resolves the two runtime-only values (the tailnet URL and the redis socket),
  # then execs whatever it was handed.
  runner = pkgs.writeShellScript "paperless-run" ''
    set -eu

    set -o allexport
    ${lib.toShellVars env}

    # CSRF/origin checking needs the address the browser actually used.
    ${tailnet.vars}
    PAPERLESS_URL="https://$TS_FQDN:${toString servePort}"

    # Paperless classifies documents with scikit-learn on top of OpenBLAS. The
    # NixOS module pins OMP_NUM_THREADS=1 unconditionally, because OpenMP
    # threading makes the classifier spin indefinitely once there are enough
    # classes -- it never finishes, it just times out (nixpkgs#240591).
    #
    # A flat 1 is also a host fact in disguise: it throws away every core on a
    # box that has them. So read the machine instead, and cap well short of the
    # thread counts that provoke the pathology. If the classifier ever does
    # hang, setting maxOmpThreads to 1 is the upstream mitigation.
    cores="$(${pkgs.coreutils}/bin/nproc 2>/dev/null || echo 1)"
    OMP_NUM_THREADS="$((cores > ${toString maxOmpThreads} ? ${toString maxOmpThreads} : cores))"

    # %t is a unit-file specifier and does not expand in a script; systemd sets
    # XDG_RUNTIME_DIR for user services, which is the same directory and just as
    # free of a hardcoded uid.
    PAPERLESS_REDIS="unix://''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}/paperless-redis.sock"

    if [ -e '${secretKeyFile}' ]; then
      # shellcheck disable=SC1091
      . '${secretKeyFile}'
    fi
    set +o allexport

    cd '${dataDir}'
    exec "$@"
  '';

  # Mirrors the NixOS module's scheduler preStart: migrate when the package
  # version moves, and keep the search index in step.
  preStart = pkgs.writeShellScript "paperless-prestart" ''
    set -eu
    versionFile='${dataDir}/src-version'
    version="$(cat "$versionFile" 2>/dev/null || echo 0)"
    if [ "$version" != '${pkg.version}' ]; then
      ${lib.getExe pkg} migrate
      echo '${pkg.version}' > "$versionFile"
    fi
    # --if-needed makes this a fast no-op once the index is current.
    ${lib.getExe pkg} document_index reindex --if-needed --no-progress-bar
  '';

  manage = pkgs.writeShellApplication {
    name = "paperless-manage";
    text = ''exec ${runner} ${lib.getExe pkg} "$@"'';
  };

  # Shared skeleton. Everything runs as this user, so no hardening beyond what
  # a user unit gives for free -- matching vaultwarden.nix rather than the
  # NixOS module's DynamicUser sandbox.
  mkUnit = {
    description,
    exec,
    after ? ["paperless-scheduler.service"],
    bindsTo ? ["paperless-scheduler.service"],
    extraService ? {},
  }: {
    Unit =
      {
        Description = description;
        After = ["network-online.target"] ++ after;
        Wants = ["network-online.target"];
        RequiresMountsFor = [root];
      }
      // lib.optionalAttrs (bindsTo != []) {BindsTo = bindsTo;};

    Service =
      {
        ExecStart = "${runner} ${exec}";
        Restart = "on-failure";
        RestartSec = 5;
      }
      // extraService;

    Install.WantedBy = ["default.target"];
  };
in {
  home.packages = [manage];

  home.activation.paperlessSetup = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

    # /srv/storage is root-owned, so the first switch needs one sudo -- same
    # one-time dance as vaultwarden's /var/lib directory.
    for dir in '${dataDir}' '${indexDir}' '${mediaDir}' '${consumeDir}'; do
      if [ ! -d "$dir" ]; then
        $DRY_RUN_CMD sudo mkdir -p "$dir"
        $DRY_RUN_CMD sudo chown "$USER":"$USER" "$dir"
        $DRY_RUN_CMD sudo chmod 700 "$dir"
      fi
    done

    # Seeded once and never rewritten: regenerating it would invalidate every
    # session and every stored password-reset link.
    if [ ! -e '${secretKeyFile}' ]; then
      $DRY_RUN_CMD ${pkgs.bash}/bin/bash -c \
        "printf 'PAPERLESS_SECRET_KEY=%s\n' \"\$(${pkgs.coreutils}/bin/tr -dc A-Za-z0-9 < /dev/urandom | ${pkgs.coreutils}/bin/head -c64)\" > '${secretKeyFile}'"
      $DRY_RUN_CMD chmod 600 '${secretKeyFile}'
    fi

    ${tailnet.serveHttps {
      port = servePort;
      target = "http://127.0.0.1:${toString port}";
    }}
  '';

  systemd.user.services = {
    # Broker for celery. Unix socket under %t, so no port and no uid anywhere.
    paperless-redis = {
      Unit.Description = "Redis broker for paperless";
      Service = {
        ExecStart = "${pkgs.redis}/bin/redis-server --port 0 --unixsocket %t/paperless-redis.sock --unixsocketperm 700 --dir %S/paperless-redis --save ''";
        StateDirectory = "paperless-redis";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = ["default.target"];
    };

    # Runs migrations before anything else touches the database, which is why
    # the other three bind to it.
    paperless-scheduler = mkUnit {
      description = "Paperless celery beat";
      exec = "${pkg}/bin/celery --app paperless beat --loglevel INFO";
      after = ["paperless-redis.service"];
      bindsTo = [];
      extraService = {
        ExecStartPre = "${runner} ${preStart}";
        # Migrations on a cold SQLite database plus a first index build.
        TimeoutStartSec = "900";
      };
    };

    paperless-task-queue = mkUnit {
      description = "Paperless celery workers";
      exec = "${pkg}/bin/celery --app paperless worker --loglevel INFO";
      # mbind, needed by the classifier, is available: no syscall filter here.
    };

    paperless-consumer = mkUnit {
      description = "Paperless document consumer";
      exec = "${lib.getExe pkg} document_consumer";
    };

    paperless-web = mkUnit {
      description = "Paperless web server";
      exec = "${lib.getExe pkg.python.pkgs.granian} --interface asginl --ws paperless.asgi:application";
      extraService = {
        Environment = [
          "PYTHONPATH=${pkg.python.pkgs.makePythonPath pkg.passthru.dependencies}:${pkg}/lib/paperless-ngx/src"
        ];
        LimitNOFILE = 65536;
      };
    };
  };
}
