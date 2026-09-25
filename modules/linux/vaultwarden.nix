# Vaultwarden on non-NixOS Debian (maui), no Docker.
#
# Home-manager only manages $HOME, so this can't use the NixOS
# `services.vaultwarden` module -- instead it's a plain systemd --user
# service running pkgs.vaultwarden. Data backend is SQLite (the default):
# a single file under /var/lib/vaultwarden.
#
# TLS is terminated by Rocket itself using a Tailscale-issued cert for this
# host's MagicDNS name (`tailscale cert`, backed by Let's Encrypt via the
# tailnet's HTTPS Certificates feature). The cert is fetched/renewed by
# `just tls-cert`, run automatically as part of `just switch` -- see
# justfile. This does not use the self-signed cert from tls-cert.nix.
#
# Bound to this host's Tailscale IP (not 0.0.0.0), so it's reachable over
# the tailnet without exposing it to the LAN -- this box has no firewall.
# The IP is resolved at service-start time (see the ExecStart wrapper below),
# not baked in from Nix eval, since it's runtime host state.
#
# /var/lib paths live outside $HOME, so activation needs a one-time sudo
# mkdir/chown -- `home-manager switch` will prompt for it.
#
# First-time setup:
#   1. Visit https://<this host>.<tailnet>.ts.net:8222, create your account.
#   2. Set SIGNUPS_ALLOWED=false in ~/.config/vaultwarden/env, then:
#        systemctl --user restart vaultwarden
#   3. (Optional) set ADMIN_TOKEN in that file to unlock /admin
#      (generate with: openssl rand -base64 48)
#
# The env file lives outside the Nix store (secrets shouldn't be
# world-readable in /nix/store) and is seeded once, never overwritten again.
{
  config,
  pkgs,
  lib,
  ...
}: let
  tailnet = import ./lib/tailnet.nix {inherit pkgs;};
in {
  home.packages = [pkgs.vaultwarden];

  home.activation.vaultwardenEnv = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

    DATA_DIR="/var/lib/vaultwarden"
    if [ ! -d "$DATA_DIR" ]; then
      $DRY_RUN_CMD sudo mkdir -p "$DATA_DIR"
      $DRY_RUN_CMD sudo chown "$USER":"$USER" "$DATA_DIR"
      $DRY_RUN_CMD sudo chmod 700 "$DATA_DIR"
    fi

    ENV_FILE="$HOME/.config/vaultwarden/env"
    if [ ! -e "$ENV_FILE" ]; then
      $DRY_RUN_CMD mkdir -p "$(dirname "$ENV_FILE")"
      $DRY_RUN_CMD bash -c "cat > '$ENV_FILE' <<'EOF'
# Managed by home-manager on first run only -- edit freely, it will not be
# overwritten again. Restart after changes: systemctl --user restart vaultwarden

# Set to false once you've created your account.
SIGNUPS_ALLOWED=true

# Uncomment and set a random value to enable the /admin diagnostics page.
# Generate with: openssl rand -base64 48
#ADMIN_TOKEN=

# The origin used for invite/reset links and as the WebAuthn relying-party ID,
# so it must be the address you actually browse to -- passkeys registered
# against the wrong origin will not verify. Tailnet name, not 127.0.0.1.
#DOMAIN=https://<this host>.<tailnet>.ts.net:8222
EOF"
      $DRY_RUN_CMD chmod 600 "$ENV_FILE"
    fi

    # Lets the service keep running after logout/reboot without an active
    # session. Enabling linger for yourself doesn't require root.
    $DRY_RUN_CMD loginctl enable-linger "$USER" 2>/dev/null || true
  '';

  systemd.user.services.vaultwarden = {
    Unit = {
      Description = "Vaultwarden password manager";
      After = ["network-online.target"];
      Wants = ["network-online.target"];
    };

    Service = {
      ExecStart = let
        start = pkgs.writeShellScript "vaultwarden-start" ''
          set -eu
          ${tailnet.vars}
          export ROCKET_ADDRESS="$TS_IP"
          exec ${pkgs.vaultwarden}/bin/vaultwarden
        '';
      in "${start}";
      EnvironmentFile = "-%h/.config/vaultwarden/env";
      Environment = [
        "DATA_FOLDER=/var/lib/vaultwarden"
        "WEB_VAULT_FOLDER=${pkgs.vaultwarden.webvault}/share/vaultwarden/vault"
        "ROCKET_PORT=8222"
        ''ROCKET_TLS={certs="/var/lib/vaultwarden-tls/cert.pem",key="/var/lib/vaultwarden-tls/key.pem"}''
      ];
      Restart = "on-failure";
      RestartSec = 5;
    };

    Install.WantedBy = ["default.target"];
  };
}
