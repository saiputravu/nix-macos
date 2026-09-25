# CouchDB, as the replication target for Obsidian Self-hosted LiveSync
# (notes.txt item 2).
#
# Why CouchDB and not Syncthing: the phone and iPad are the devices that matter
# here, and LiveSync is the only real-time option with a first-class iOS
# Obsidian story. nixpkgs ships couchdb 3.5, so this stays a plain user unit --
# no container.
#
# Loopback only, published to the tailnet by `tailscale serve` on :8446.
#
# Config layering follows the NixOS couchdb module: the package's default.ini,
# then the Nix-built ini below, then a writable local.ini that CouchDB itself
# rewrites (it replaces the seeded admin password with its hash on first
# start). That last file is why the admin credential cannot live in the store.
#
# The vault's git history, ignore rules and the _inbox drain live next door in
# ./vault-sync.nix.
{
  config,
  pkgs,
  lib,
  ...
}: let
  tailnet = import ./lib/tailnet.nix {inherit pkgs;};

  pkg = pkgs.couchdb3;

  dbDir = "/srv/storage/couchdb";
  localIni = "${dbDir}/local.ini";
  port = 5984;
  servePort = 8446;

  # Where the generated admin password is kept in readable form -- CouchDB
  # hashes the copy in local.ini on first start, so without this it would be
  # unrecoverable.
  passwordFile = "${config.xdg.configHome}/couchdb/admin-password";

  nixIni = pkgs.writeText "couchdb-nix.ini" ''
    [couchdb]
    database_dir = ${dbDir}
    view_index_dir = ${dbDir}
    single_node = true
    ; LiveSync chunks large notes, but attachments still need headroom.
    max_document_size = 50000000

    [chttpd]
    port = ${toString port}
    bind_address = 127.0.0.1
    require_valid_user = true
    max_http_request_size = 4294967296
    enable_cors = true

    [chttpd_auth]
    require_valid_user = true
    authentication_redirect = /_utils/session.html

    [httpd]
    enable_cors = true
    WWW-Authenticate = Basic realm="couchdb"

    ; Obsidian is not a browser origin, so CORS has to name its schemes
    ; explicitly -- app:// on desktop, capacitor:// on iOS.
    [cors]
    credentials = true
    origins = app://obsidian.md,capacitor://localhost,http://localhost
    headers = accept, authorization, content-type, origin, referer
    methods = GET,PUT,POST,HEAD,DELETE
    max_age = 3600

    [log]
    level = warning
  '';
in {
  home.packages = [pkg];

  home.activation.couchdbSetup = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

    if [ ! -d "${dbDir}" ]; then
      $DRY_RUN_CMD sudo mkdir -p "${dbDir}"
      $DRY_RUN_CMD sudo chown "$USER":"$USER" "${dbDir}"
      $DRY_RUN_CMD sudo chmod 700 "${dbDir}"
    fi

    # Seeded once. CouchDB rewrites this file in place, so it must never be
    # regenerated: doing so would lock out every device already replicating.
    if [ ! -e "${localIni}" ]; then
      $DRY_RUN_CMD mkdir -p "$(dirname "${passwordFile}")"
      $DRY_RUN_CMD ${pkgs.bash}/bin/bash -c '
        pw="$(${pkgs.coreutils}/bin/tr -dc A-Za-z0-9 < /dev/urandom | ${pkgs.coreutils}/bin/head -c32)"
        printf "%s\n" "$pw" > "${passwordFile}"
        chmod 600 "${passwordFile}"
        # CouchDB replaces this plaintext with a hash the first time it starts.
        printf "[admins]\nsai = %s\n" "$pw" > "${localIni}"
        chmod 600 "${localIni}"
      '
      echo "couchdb: admin password generated -> ${passwordFile}"
    fi

    if [ ! -e "${dbDir}/.erlang.cookie" ]; then
      $DRY_RUN_CMD ${pkgs.bash}/bin/bash -c '
        ${pkgs.coreutils}/bin/dd if=/dev/urandom bs=16 count=1 status=none \
          | ${pkgs.coreutils}/bin/base64 > "${dbDir}/.erlang.cookie"
        chmod 600 "${dbDir}/.erlang.cookie"
      '
    fi

    ${tailnet.serveHttps {
      port = servePort;
      target = "http://127.0.0.1:${toString port}";
    }}
  '';

  systemd.user.services.couchdb = {
    Unit = {
      Description = "CouchDB (Obsidian LiveSync replication target)";
      After = ["network-online.target"];
      Wants = ["network-online.target"];
      RequiresMountsFor = [dbDir];
    };

    Service = {
      ExecStart = "${pkg}/bin/couchdb";
      Environment = [
        # Layered lowest-precedence first; the writable file wins.
        "ERL_FLAGS=-couch_ini ${pkg}/etc/default.ini ${nixIni} ${localIni}"
        "COUCHDB_ARGS_FILE=${pkg}/etc/vm.args"
        "HOME=${dbDir}"
      ];
      Restart = "on-failure";
      RestartSec = 5;
    };

    Install.WantedBy = ["default.target"];
  };
}
