# Fixes a boot race on non-NixOS boxes where /nix lives on its own mount.
#
# nix-daemon.socket and nix-daemon.service are symlinks from
# /etc/systemd/system into /nix/store. At boot, systemd tries to activate
# them (via sockets.target / multi-user.target) before nix.mount has
# mounted /nix -- so the very first attempt to load the symlinked unit
# fails with ENOENT and is never retried, leaving the daemon socket
# permanently inactive until someone manually starts it.
#
# These drop-ins live directly on the root filesystem (not through the
# /nix symlink), so systemd can read the ordering constraint before /nix
# is mounted, and waits for nix.mount before trying to load the real unit.
{
  config,
  pkgs,
  lib,
  ...
}: {
  home.activation.nixDaemonMountOrder = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

    CHANGED=0
    for unit in nix-daemon.socket nix-daemon.service; do
      DROPIN_DIR="/etc/systemd/system/$unit.d"
      DROPIN="$DROPIN_DIR/nix-mount-order.conf"
      DROPIN_TMP="$(mktemp)"

      printf '%s\n' "[Unit]" "After=nix.mount" "RequiresMountsFor=/nix" > "$DROPIN_TMP"

      if ! sudo cmp -s "$DROPIN_TMP" "$DROPIN" 2>/dev/null; then
        $DRY_RUN_CMD sudo mkdir -p "$DROPIN_DIR"
        $DRY_RUN_CMD sudo install -m 644 -o root -g root "$DROPIN_TMP" "$DROPIN"
        CHANGED=1
      fi
      rm -f "$DROPIN_TMP"
    done

    if [ "$CHANGED" = 1 ]; then
      $DRY_RUN_CMD sudo systemctl daemon-reload
    fi
  '';
}
