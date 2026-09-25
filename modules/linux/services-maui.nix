# Services that only run on maui, the always-on Debian box.
#
# Kept out of ./home.nix because noble2 (the VPS) shares that file and must not
# pick any of this up. flake.nix lists this module for maui only.
#
# Convention for everything imported here: a `systemd.user.service` unless the
# thing genuinely needs root or a privileged port, in which case it installs a
# root-owned unit through ./lib/system-unit.nix. No host IP or MagicDNS name is
# ever written into a module -- see ./lib/tailnet.nix for why and how.
_: {
  imports = [
    ./vaultwarden.nix
    ./blocky.nix
    ./ntfy.nix
    ./paperless.nix
    ./couchdb.nix
    ./vault-sync.nix
    ./digest.nix
    ./openclaw.nix
  ];
}
