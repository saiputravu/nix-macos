# DNS sinkhole for the whole tailnet (maui).
#
# Every device gets filtered DNS wherever it is -- including the phone on
# cellular -- by pointing the tailnet's global nameserver at this host in the
# Tailscale admin console (`just dns-info` prints the address to paste). That
# is what replaces per-device AdGuard, and because every upstream here is
# DNS-over-HTTPS it also removes the reason to route DNS through the VPS.
#
# Needs :53, so unlike vaultwarden this is a root-owned system unit installed by
# an activation script -- see ./lib/system-unit.nix.
#
# The config is built by Nix but *rendered at start time*: blocky wants literal
# addresses, and this host's tailnet IP and LAN gateway are runtime state, not
# things to write into the store. ExecStartPre fills them in; everything else
# below is the real config.
{
  config,
  pkgs,
  lib,
  ...
}: let
  tailnet = import ./lib/tailnet.nix {inherit pkgs;};
  inherit (import ./lib/system-unit.nix {inherit pkgs lib;}) mkSystemUnit;

  # Flip to false to fall back to plain UDP upstreams (notes.txt item 4: "DNS
  # over HTTPs on toggle"). One line here, then `just switch`.
  useDoH = true;

  upstreams =
    if useDoH
    then ''
      - https://dns.quad9.net/dns-query
            - https://cloudflare-dns.com/dns-query''
    else ''
      - tcp+udp:9.9.9.9
            - tcp+udp:1.1.1.1'';

  # @TS_IP@ and @LAN_MAPPING@ are the only placeholders; ExecStartPre fills them.
  configTemplate = pkgs.writeText "blocky-config.yml.in" ''
    upstreams:
      groups:
        default:
          ${upstreams}
      strategy: parallel_best
      timeout: 2s

    # Resolves the upstream hostnames above. Without this blocky would have to
    # use itself to find its own resolver.
    bootstrapDns:
      - upstream: tcp+udp:9.9.9.9
      - upstream: tcp+udp:1.1.1.1

    connectIPVersion: v4

    blocking:
      denylists:
        ads:
          - https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
          - https://big.oisd.nl
      allowlists:
        ads:
          # False positives go here, then `just switch`. Kept in Nix on purpose:
          # an allowlist edited in place on the box would not survive a rebuild.
          - |
            # example.com
      clientGroupsBlock:
        default:
          - ads
      blockType: zeroIp
      blockTTL: 1m
      loading:
        refreshPeriod: 24h
        downloads:
          timeout: 60s
          attempts: 3
          cooldown: 2s
        # Keep serving the previous lists if a download fails at startup rather
        # than refusing to resolve anything.
        strategy: fast

    caching:
      minTime: 5m
      maxTime: 30m
      prefetching: true

    ports:
      dns: @DNS_BIND@
      http: 127.0.0.1:4000

    # Privacy: this box sees every lookup from every device, so it writes none
    # of them down.
    log:
      level: warn
    queryLog:
      type: none

    conditional:
      fallbackUpstream: false
      mapping:
        # MagicDNS. 100.100.100.100 is Tailscale's fixed resolver address, not
        # anything specific to this tailnet.
        ts.net: tcp+udp:100.100.100.100
    @LAN_MAPPING@
  '';

  render = pkgs.writeShellScript "blocky-render-config" ''
    set -eu
    ${tailnet.vars}

    # Bind to loopback and the tailnet only. This box has no firewall, so
    # 0.0.0.0 would hand the LAN an open resolver.
    if [ "$TS_IP" = "127.0.0.1" ]; then
      DNS_BIND="127.0.0.1:53"
    else
      DNS_BIND="127.0.0.1:53,$TS_IP:53"
    fi

    # Forward the LAN's own search domain to the router, so router-assigned
    # hostnames keep resolving. Both values are read from live system state:
    # the search domain from resolv.conf (minus the tailnet's own suffix), the
    # gateway from the routing table. If either is missing, the mapping is
    # simply left out.
    LAN_DOMAIN="$(${pkgs.gawk}/bin/awk '/^search/ {for (i=2;i<=NF;i++) if ($i !~ /ts\.net$/) {print $i; exit}}' /etc/resolv.conf || true)"
    LAN_GW="$(${pkgs.iproute2}/bin/ip route show default | ${pkgs.gawk}/bin/awk '/default via/ {print $3; exit}' || true)"
    if [ -n "$LAN_DOMAIN" ] && [ -n "$LAN_GW" ]; then
      LAN_MAPPING="    $LAN_DOMAIN: tcp+udp:$LAN_GW"
    else
      LAN_MAPPING=""
    fi

    ${pkgs.gnused}/bin/sed \
      -e "s|@DNS_BIND@|$DNS_BIND|g" \
      -e "s|@LAN_MAPPING@|$LAN_MAPPING|g" \
      ${configTemplate} > /run/blocky/config.yml

    # Refuse to start on a config this blocky cannot parse, rather than dropping
    # DNS for the whole tailnet.
    ${pkgs.blocky}/bin/blocky validate --config /run/blocky/config.yml
  '';
in {
  home.activation.blockyService = lib.hm.dag.entryAfter ["writeBoundary"] (
    mkSystemUnit {
      name = "blocky.service";
      text = ''
        [Unit]
        Description=blocky DNS sinkhole (Nix-managed, do not edit by hand)
        Documentation=https://0xerr0r.github.io/blocky/
        Wants=network-online.target
        After=network-online.target
        # Needs tailscaled up to learn which address to bind.
        Wants=tailscaled.service
        After=tailscaled.service

        [Service]
        Type=simple
        DynamicUser=yes
        RuntimeDirectory=blocky
        RuntimeDirectoryMode=0750
        ExecStartPre=${render}
        ExecStart=${pkgs.blocky}/bin/blocky --config /run/blocky/config.yml
        # :53 is privileged (ip_unprivileged_port_start is 1024 on this box).
        AmbientCapabilities=CAP_NET_BIND_SERVICE
        CapabilityBoundingSet=CAP_NET_BIND_SERVICE
        NoNewPrivileges=yes
        ProtectSystem=strict
        ProtectHome=yes
        PrivateTmp=yes
        # Retry rather than give up: a boot where tailscaled is slow must not
        # leave the tailnet without a resolver.
        Restart=on-failure
        RestartSec=5

        [Install]
        WantedBy=multi-user.target
      '';
    }
  );
}
