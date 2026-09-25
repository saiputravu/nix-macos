# Self-signed TLS cert for local services that want HTTPS without a public
# CA (currently used by vaultwarden.nix). Lives under /var/lib, outside
# $HOME, so needs a one-time sudo mkdir/chown -- see tailscale.nix.
#
# Tailscale-specific: the cert's SANs are this host's Tailscale IP and
# MagicDNS name, looked up via the `tailscale` CLI. Only import this on
# hosts that also import tailscale.nix.
{
  config,
  pkgs,
  lib,
  ...
}: let
  tailnet = import ./lib/tailnet.nix {inherit pkgs;};
in {
  home.activation.hostTlsCert = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

    CERT_DIR="/var/lib/host-tls"
    if [ ! -d "$CERT_DIR" ]; then
      $DRY_RUN_CMD sudo mkdir -p "$CERT_DIR"
      $DRY_RUN_CMD sudo chown "$USER":"$USER" "$CERT_DIR"
      $DRY_RUN_CMD sudo chmod 700 "$CERT_DIR"
    fi

    if [ ! -e "$CERT_DIR/cert.pem" ] || [ ! -e "$CERT_DIR/key.pem" ]; then
      ${tailnet.vars}
      $DRY_RUN_CMD ${pkgs.openssl}/bin/openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.pem" -days 3650 \
        -subj "/CN=$TS_FQDN" \
        -addext "subjectAltName=DNS:$TS_FQDN,DNS:''${TS_FQDN%%.*},DNS:localhost,IP:127.0.0.1,IP:$TS_IP"
      $DRY_RUN_CMD chmod 600 "$CERT_DIR/key.pem"
    fi
  '';
}
