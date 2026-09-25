# openclaw: WhatsApp in, an agent on this box out. notes.txt items 7 and 8.
#
# What it is: a gateway process that links to WhatsApp as a WhatsApp Web
# (Baileys) *linked device* -- `openclawctl channels login --channel whatsapp`
# prints a QR, you scan it under WhatsApp -> Settings -> Linked Devices, and the
# session persists under the state dir and reconnects by itself. Same trust
# model as WhatsApp Web in a browser: an unofficial client holding a real
# session, which is why a dedicated number is safer than a personal one.
#
# nixpkgs marks this package insecure, and the reason is worth reading rather
# than working around:
#
#   "uses LLMs to parse untrusted content, making it vulnerable to prompt
#    injection, while having full access to system by default"
#
# Every message that arrives is untrusted input to a model with tools. So this
# is the only service here that does *not* run as me. It gets a dedicated system
# user and a system unit with ProtectHome, ProtectSystem=strict and a
# ReadWritePaths list of exactly two directories: its own state, and the repos
# it exists to work on. ~/.ssh, ~/.config/vaultwarden/env, the gcalcli token and
# every paperless document are outside that boundary and stay invisible to it.
# There is no sudo anywhere in this file's runtime path.
#
# Two deliberate consequences of that confinement:
#
#   - It can read, edit and commit in /srv/storage/repos, but it cannot push:
#     the push key lives in my home directory, which it cannot see. Review and
#     push stay a human step.
#   - Claude Code runs as the openclaw user, so it needs its own login --
#     `openclawctl` is the way to get a shell's worth of that user's environment
#     without handing anything else over.
#
# ntfy remains the alerting path even with this running (see ./ntfy.nix):
# one-way, no model in the loop, still works when this service is down.
#
# Reachable at https://<this host>.<tailnet>.ts.net:8447 via `tailscale serve`.
# The gateway itself binds loopback and requires a token regardless, because
# anything on the tailnet can reach a loopback port once it is served.
#
# Build note: openclaw's pnpm fetch pulls every platform's prebuilt binaries,
# several GB in one go, and times out on a slow link. It is a fixed-output
# derivation, so a one-off retry with longer timeouts lands on exactly the same
# store path and the normal build then finds it:
#
#   nix-build -E 'with import <nixpkgs> {}; openclaw.pnpmDeps.overrideAttrs {
#     npm_config_fetch_timeout = "1200000"; npm_config_network_concurrency = "4"; }'
#
# First-time setup (deferred to the end of the build-out):
#   openclawctl models auth login --provider anthropic --method cli
#   openclawctl channels login --channel whatsapp     # scan the QR
#   # then add the sending number to channels.whatsapp.allowFrom
{
  config,
  inputs,
  pkgs,
  lib,
  ...
}: let
  tailnet = import ./lib/tailnet.nix {inherit pkgs;};
  inherit (import ./lib/system-unit.nix {inherit pkgs lib;}) mkSystemUnit;

  user = "openclaw";
  stateDir = "/var/lib/openclaw";
  workspace = "/srv/storage/repos";

  configFile = "${stateDir}/openclaw.json";
  envFile = "${stateDir}/.env";

  # Gateway default. WS and HTTP are multiplexed onto this one port.
  port = 18789;
  servePort = 8447;

  claude = inputs.claude-code-nix.packages.${pkgs.system}.default;

  # What the agent's `exec` tool can reach. Deliberately a short list: this is
  # the toolbox, and anything not in it is not available to a prompt-injected
  # session either. openssh is absent on purpose -- see the header.
  toolchain = lib.makeBinPath [
    pkgs.bashInteractive
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.gawk
    pkgs.git
    pkgs.ripgrep
    pkgs.fd
    pkgs.jq
    claude
  ];

  # Seeded once, then owned by openclaw: `channels add`, `pairing approve` and
  # the Control UI all write back to this file, so it cannot be a store path.
  # Everything below is a starting point, not a managed value.
  configSeed = pkgs.writeText "openclaw.json" ''
    // Seeded by modules/linux/openclaw.nix on first activation. openclaw owns
    // this file from here on -- edits made through the CLI or the Control UI
    // will not be reverted, and nix will not rewrite it.
    {
      gateway: {
        port: ${toString port},
        // tailscale serve is the only thing in front of this.
        bind: "loopback",
        auth: {
          mode: "token",
          // Resolved from the environment, so no token is written down here.
          token: "''${OPENCLAW_GATEWAY_TOKEN}",
        },
      },

      channels: {
        whatsapp: {
          // allowFrom starts empty: until a number is added by hand, nothing
          // and nobody can start a conversation with the agent.
          dmPolicy: "allowlist",
          allowFrom: [],
          // Group chats are a prompt-injection surface with more than one
          // author in it.
          groupPolicy: "disabled",
        },
      },

      agents: {
        defaults: {
          workspace: "${workspace}",
          cliBackends: {
            "claude-cli": {
              // Absolute: this unit's PATH is its own, not my login shell's.
              command: "${claude}/bin/claude",
            },
          },
        },
      },
    }
  '';
in {
  # Talk to the daemon's state as the daemon's user. Every manual step in the
  # header goes through this; running plain `openclaw` as me would build a
  # second, unrelated state directory in my home.
  home.packages = [
    (pkgs.writeShellApplication {
      name = "openclawctl";
      text = ''
        exec sudo -u ${user} -H env \
          OPENCLAW_STATE_DIR=${stateDir} \
          OPENCLAW_CONFIG_PATH=${configFile} \
          PATH=${toolchain} \
          ${pkgs.openclaw}/bin/openclaw "$@"
      '';
    })
  ];

  home.activation.openclawSetup = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

    # A system account with no shell and no login: the only way into it is the
    # unit, or `sudo -u` from an account that already has sudo.
    if ! id -u ${user} >/dev/null 2>&1; then
      $DRY_RUN_CMD sudo useradd --system --user-group \
        --home-dir ${stateDir} --create-home \
        --shell /usr/sbin/nologin ${user}
    fi

    if [ ! -d "${stateDir}" ]; then
      $DRY_RUN_CMD sudo mkdir -p "${stateDir}"
    fi
    $DRY_RUN_CMD sudo chown ${user}:${user} "${stateDir}"
    # 0700: my own account has no business reading the agent's session logs
    # either, and the WhatsApp credentials live under here.
    $DRY_RUN_CMD sudo chmod 700 "${stateDir}"

    # The repos stay mine. The agent gets at them through my *group* rather than
    # by owning anything: my home is 0700, so group membership grants it nothing
    # outside the directories deliberately made group-writable below -- and the
    # unit's ProtectHome closes even that off for the daemon itself.
    if [ ! -d "${workspace}" ]; then
      $DRY_RUN_CMD sudo mkdir -p "${workspace}"
      $DRY_RUN_CMD sudo chown "$USER":"$USER" "${workspace}"
    fi
    if ! id -nG ${user} | tr ' ' '\n' | grep -qx "$USER"; then
      $DRY_RUN_CMD sudo usermod -aG "$USER" ${user}
    fi
    # setgid so anything the agent creates keeps my group, and g+w so I can edit
    # it afterwards. Individual repos underneath need the same two bits before
    # the agent can write in them -- not applied recursively on purpose.
    $DRY_RUN_CMD sudo chmod g+ws "${workspace}"

    if [ ! -e "${envFile}" ]; then
      $DRY_RUN_CMD sudo ${pkgs.bash}/bin/bash -c 'umask 077; \
        printf "OPENCLAW_GATEWAY_TOKEN=%s\n" "$(${pkgs.openssl}/bin/openssl rand -hex 32)" > "${envFile}"; \
        chown ${user}:${user} "${envFile}"'
    fi

    if [ ! -e "${configFile}" ]; then
      $DRY_RUN_CMD sudo install -m 600 -o ${user} -g ${user} \
        "${configSeed}" "${configFile}"
    fi

    ${tailnet.serveHttps {
      port = servePort;
      target = "http://127.0.0.1:${toString port}";
    }}
  '';

  home.activation.openclawService = lib.hm.dag.entryAfter ["openclawSetup"] (
    mkSystemUnit {
      name = "openclaw.service";
      text = ''
        [Unit]
        Description=openclaw gateway (Nix-managed, do not edit by hand)
        Documentation=https://openclaw.ai
        Wants=network-online.target
        After=network-online.target
        After=tailscaled.service

        [Service]
        Type=simple
        User=${user}
        Group=${user}
        WorkingDirectory=${stateDir}
        Environment=HOME=${stateDir}
        Environment=OPENCLAW_STATE_DIR=${stateDir}
        Environment=OPENCLAW_CONFIG_PATH=${configFile}
        # Keeps restarts in-process, which is what the project recommends for
        # small always-on hosts and what keeps the PID systemd tracks correct.
        Environment=OPENCLAW_NO_RESPAWN=1
        Environment=NODE_COMPILE_CACHE=${stateDir}/.cache/node-compile
        Environment=PATH=${toolchain}
        # Files it writes in the shared repos stay editable by me.
        UMask=0002
        # Seeded by activation; `-` so a first boot before seeding is not fatal.
        EnvironmentFile=-${envFile}
        ExecStart=${pkgs.openclaw}/bin/openclaw gateway
        Restart=always
        RestartSec=2
        # Node cold start plus plugin load on a spinning disk.
        TimeoutStartSec=90

        # The containment the nixpkgs insecure marking calls for. ProtectHome is
        # the load-bearing one: it is what keeps my ssh keys, vaultwarden env and
        # gcalcli token out of reach of anything a message talks the model into.
        NoNewPrivileges=yes
        ProtectHome=yes
        ProtectSystem=strict
        ReadWritePaths=${stateDir} ${workspace}
        PrivateTmp=yes
        PrivateDevices=yes
        ProtectClock=yes
        ProtectHostname=yes
        ProtectKernelTunables=yes
        ProtectKernelModules=yes
        ProtectControlGroups=yes
        RestrictNamespaces=yes
        RestrictRealtime=yes
        RestrictSUIDSGID=yes
        LockPersonality=yes
        CapabilityBoundingSet=
        # No SystemCallFilter: node's syscall surface shifts between releases,
        # and a filter that silently kills the gateway after an update would buy
        # less than the namespace restrictions above already do.

        [Install]
        WantedBy=multi-user.target
      '';
    }
  );
}
