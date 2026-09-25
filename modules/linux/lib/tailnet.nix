# This host's tailnet identity, resolved at runtime instead of baked into the
# store.
#
# The tailnet IP and the MagicDNS name are host state: they change when a
# machine is re-registered, and they differ on every box this config gets
# cloned onto. So nothing here may be written down in a module -- services that
# need an address resolve it in their ExecStart wrapper (the idiom
# vaultwarden.nix already uses for ROCKET_ADDRESS), and anything that needs it
# in a config file renders that file at start time.
#
# Two ways in:
#
#   ${tailnet.vars}            sourceable snippet, for units and activation
#   tailnet-vars               the same thing as a CLI, for the justfile
#
# Both export TS_IP, TS_SUFFIX and TS_FQDN.
{pkgs}: rec {
  # Never fails the calling script: a stopped or unregistered tailscaled just
  # yields the loopback fallback. That matters because home-manager activation
  # runs under `set -eu`, and because these services start at boot, possibly
  # before tailscaled has come up.
  vars = ''
    TS_IP="$(${pkgs.tailscale}/bin/tailscale ip -4 2>/dev/null || echo 127.0.0.1)"
    TS_STATUS="$(${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null || echo '{}')"
    TS_SUFFIX="$(printf '%s' "$TS_STATUS" | ${pkgs.jq}/bin/jq -r '.MagicDNSSuffix // empty')"
    # Self.DNSName is the authoritative FQDN and carries a trailing dot. Falling
    # back to <short hostname>.<suffix> keeps the behaviour tls-cert.nix had
    # before this snippet was shared.
    TS_FQDN="$(printf '%s' "$TS_STATUS" | ${pkgs.jq}/bin/jq -r '.Self.DNSName // empty' | ${pkgs.gnused}/bin/sed 's/\.$//')"
    if [ -z "$TS_FQDN" ]; then
      TS_FQDN="$(${pkgs.coreutils}/bin/uname -n | ${pkgs.coreutils}/bin/cut -d. -f1)''${TS_SUFFIX:+.$TS_SUFFIX}"
    fi
    export TS_IP TS_SUFFIX TS_FQDN
  '';

  # `eval "$(tailnet-vars)"` -- how the justfile gets at the same values without
  # duplicating the lookup in shell.
  pkg = pkgs.writeShellApplication {
    name = "tailnet-vars";
    text = ''
      ${vars}
      printf 'TS_IP=%s\nTS_SUFFIX=%s\nTS_FQDN=%s\n' "$TS_IP" "$TS_SUFFIX" "$TS_FQDN"
    '';
  };

  # Publish a loopback port on this node's tailnet name over HTTPS, using the
  # tailnet's own Let's Encrypt cert. Renews itself, and needs neither an IP nor
  # an FQDN written down anywhere -- which is why new services use this rather
  # than vaultwarden's `just tls-cert` arrangement.
  #
  # Idempotent: re-running a switch with the mapping already in place is a no-op.
  serveHttps = {
    port,
    target,
  }: ''
    ${vars}
    if ! sudo ${pkgs.tailscale}/bin/tailscale serve status --json 2>/dev/null \
      | ${pkgs.jq}/bin/jq -e --arg k "$TS_FQDN:${toString port}" '.Web // {} | has($k)' >/dev/null; then
      $DRY_RUN_CMD sudo ${pkgs.tailscale}/bin/tailscale serve --bg --yes \
        --https=${toString port} ${target}
    fi
  '';
}
