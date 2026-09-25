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
}: let
  tailnet = import ./lib/tailnet.nix {inherit pkgs;};
  inherit (import ./lib/system-unit.nix {inherit pkgs lib;}) mkSystemUnit mkSystemFile;
in {
  # tailnet-vars is what the justfile and the other service modules use to
  # resolve this host's tailnet IP/FQDN instead of hardcoding either.
  home.packages = [pkgs.tailscale tailnet.pkg];

  # After activation, authenticate this machine with: sudo tailscale up
  home.activation.tailscaleService = lib.hm.dag.entryAfter ["writeBoundary"] (
    mkSystemUnit {
      name = "tailscaled.service";
      text = ''
        [Unit]
        Description=Tailscale node agent (Nix-managed, do not edit by hand)
        Documentation=https://tailscale.com/kb/
        Wants=network-pre.target
        After=network-pre.target
        Wants=network-online.target
        After=network-online.target

        [Service]
        ExecStartPre=${pkgs.tailscale}/bin/tailscaled --cleanup
        ExecStart=${pkgs.tailscale}/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock --port 41641
        ExecStopPost=${pkgs.tailscale}/bin/tailscaled --cleanup
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
      '';
    }
    +
    # Required for --advertise-exit-node / subnet routing to actually forward
    # traffic; https://tailscale.com/s/ip-forwarding
    mkSystemFile {
      path = "/etc/sysctl.d/99-tailscale.conf";
      text = ''
        net.ipv4.ip_forward = 1
        net.ipv6.conf.all.forwarding = 1
      '';
      onChange = ''$DRY_RUN_CMD sudo sysctl --system'';
    }
  );
}
