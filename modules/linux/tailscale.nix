# Tailscale on non-NixOS Debian (maui).
#
# Home-manager only manages $HOME, so it can't use the NixOS
# `services.tailscale` module. Instead: install the package via Nix, then use
# a root-privileged activation script (sudo, prompts for password on
# `home-manager switch`) to install+enable a systemd unit that runs the
# Nix-built tailscaled. This mirrors the unit shipped in tailscale's own .deb.
{
  config,
  pkgs,
  lib,
  ...
}: {
  home.packages = [pkgs.tailscale];

  # After activation, authenticate this machine with: sudo tailscale up
  home.activation.tailscaleService = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

    TAILSCALED_BIN="${pkgs.tailscale}/bin/tailscaled"
    UNIT_PATH="/etc/systemd/system/tailscaled.service"
    UNIT_TMP="$(mktemp)"

    cat > "$UNIT_TMP" <<EOF
    [Unit]
    Description=Tailscale node agent (Nix-managed, do not edit by hand)
    Documentation=https://tailscale.com/kb/
    Wants=network-pre.target
    After=network-pre.target
    Wants=network-online.target
    After=network-online.target

    [Service]
    ExecStartPre=$TAILSCALED_BIN --cleanup
    ExecStart=$TAILSCALED_BIN --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock --port 41641
    ExecStopPost=$TAILSCALED_BIN --cleanup
    Restart=on-failure
    RuntimeDirectory=tailscale
    RuntimeDirectoryMode=0755
    StateDirectory=tailscale
    StateDirectoryMode=0700
    CacheDirectory=tailscale
    CacheDirectoryMode=0750
    Type=notify

    [Install]
    WantedBy=multi-user.target
    EOF

    if ! sudo cmp -s "$UNIT_TMP" "$UNIT_PATH" 2>/dev/null; then
      $DRY_RUN_CMD sudo install -m 644 -o root -g root "$UNIT_TMP" "$UNIT_PATH"
      $DRY_RUN_CMD sudo systemctl daemon-reload
      $DRY_RUN_CMD sudo systemctl restart tailscaled.service
    fi
    rm -f "$UNIT_TMP"

    $DRY_RUN_CMD sudo systemctl enable --now tailscaled.service

    # Required for --advertise-exit-node / subnet routing to actually forward
    # traffic; https://tailscale.com/s/ip-forwarding
    SYSCTL_PATH="/etc/sysctl.d/99-tailscale.conf"
    SYSCTL_TMP="$(mktemp)"
    cat > "$SYSCTL_TMP" <<EOF
    net.ipv4.ip_forward = 1
    net.ipv6.conf.all.forwarding = 1
    EOF

    if ! sudo cmp -s "$SYSCTL_TMP" "$SYSCTL_PATH" 2>/dev/null; then
      $DRY_RUN_CMD sudo install -m 644 -o root -g root "$SYSCTL_TMP" "$SYSCTL_PATH"
      $DRY_RUN_CMD sudo sysctl --system
    fi
    rm -f "$SYSCTL_TMP"
  '';
}
