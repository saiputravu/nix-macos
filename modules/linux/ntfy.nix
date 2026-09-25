# Self-hosted ntfy: the way this box messages me (notes.txt item 6).
#
# One-way, no LLM in the loop, so it stays the alerting path even after
# openclaw lands -- a backup that fails at 03:00 should not depend on an agent
# being healthy.
#
# Listens on loopback only and is published to the tailnet by `tailscale serve`
# (HTTPS on :8443, tailnet cert, renews itself). Nothing here writes down this
# host's name or address: see ./lib/tailnet.nix.
#
# iOS needs `upstream-base-url`. A self-hosted server cannot talk to APNs, so
# ntfy.sh is used purely as a wake-up relay: it receives a hash of the topic
# name and nothing else -- no message body, no title.
#
# First-time setup (deferred to the end of the build-out):
#   ntfy user add --role=admin sai
#   ntfy token add sai            # paste into ~/.config/ntfy/token
#   ntfy access sai alerts rw
{
  config,
  pkgs,
  lib,
  ...
}: let
  tailnet = import ./lib/tailnet.nix {inherit pkgs;};

  dataDir = "/var/lib/ntfy";
  port = 2586;
  servePort = 8443;
  topic = "alerts";

  serverConfig = pkgs.writeText "ntfy-server.yml" ''
    # base-url is deliberately absent: it is this host's tailnet FQDN, which is
    # runtime state. The ExecStart wrapper supplies it as NTFY_BASE_URL.
    listen-http: "127.0.0.1:${toString port}"

    auth-file: "${dataDir}/user.db"
    # Nothing is readable or writable without a token, so the topic name is not
    # load-bearing as a secret.
    auth-default-access: "deny-all"
    enable-signup: false
    enable-login: true

    cache-file: "${dataDir}/cache.db"
    cache-duration: "12h"

    # Relay for iOS push. Topic hashes only.
    upstream-base-url: "https://ntfy.sh"

    # tailscale serve is the only thing in front of this.
    behind-proxy: true
  '';

  # What every other module in here calls to reach me.
  notify = pkgs.writeShellApplication {
    name = "notify";
    runtimeInputs = [pkgs.curl];
    text = ''
      # notify [-t TITLE] [-p PRIORITY] [-T TOPIC] MESSAGE...
      #
      # Publishes over loopback rather than the tailnet name: local callers
      # should not depend on DNS, TLS, or tailscaled being up.
      title=""
      priority="default"
      topic="${topic}"
      while getopts ":t:p:T:" opt; do
        case "$opt" in
          t) title="$OPTARG" ;;
          p) priority="$OPTARG" ;;
          T) topic="$OPTARG" ;;
          *) echo "usage: notify [-t title] [-p priority] [-T topic] message..." >&2; exit 2 ;;
        esac
      done
      shift $((OPTIND - 1))

      message="$*"
      if [ -z "$message" ]; then
        message="$(cat)"      # allow: some-command | notify -t "..."
      fi

      token_file="''${XDG_CONFIG_HOME:-$HOME/.config}/ntfy/token"
      if [ ! -r "$token_file" ]; then
        echo "notify: no token at $token_file -- run 'ntfy token add <user>' and save it there" >&2
        exit 1
      fi

      curl --silent --show-error --fail \
        -H "Authorization: Bearer $(cat "$token_file")" \
        -H "Title: ''${title:-maui}" \
        -H "Priority: $priority" \
        -d "$message" \
        "http://127.0.0.1:${toString port}/$topic" >/dev/null
    '';
  };
in {
  home.packages = [pkgs.ntfy-sh notify];

  home.activation.ntfySetup = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

    if [ ! -d "${dataDir}" ]; then
      $DRY_RUN_CMD sudo mkdir -p "${dataDir}"
      $DRY_RUN_CMD sudo chown "$USER":"$USER" "${dataDir}"
      $DRY_RUN_CMD sudo chmod 700 "${dataDir}"
    fi

    ${tailnet.serveHttps {
      port = servePort;
      target = "http://127.0.0.1:${toString port}";
    }}
  '';

  systemd.user.services.ntfy = {
    Unit = {
      Description = "ntfy notification server";
      After = ["network-online.target"];
      Wants = ["network-online.target"];
    };

    Service = {
      ExecStart = let
        start = pkgs.writeShellScript "ntfy-start" ''
          set -eu
          ${tailnet.vars}
          # The address iOS subscribes to, and the origin ntfy hands to clients.
          export NTFY_BASE_URL="https://$TS_FQDN:${toString servePort}"
          exec ${pkgs.ntfy-sh}/bin/ntfy serve --config ${serverConfig}
        '';
      in "${start}";
      Restart = "on-failure";
      RestartSec = 5;
    };

    Install.WantedBy = ["default.target"];
  };
}
