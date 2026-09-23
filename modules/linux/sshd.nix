# sshd hardening on non-NixOS Debian (maui), via a root-privileged
# home-manager activation script (sudo, prompts for password on
# `home-manager switch`).
#
# Debian's stock /etc/ssh/sshd_config has `Include /etc/ssh/sshd_config.d/*.conf`
# near the very top, so a drop-in there wins first-match-wins over the (mostly
# commented-out) defaults later in the file -- no need to touch the main file.
{
  config,
  pkgs,
  lib,
  ...
}: {
  home.activation.sshdHardening = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

    DROPIN_PATH="/etc/ssh/sshd_config.d/10-nix-managed.conf"
    DROPIN_TMP="$(mktemp)"

    cat > "$DROPIN_TMP" <<EOF
    # Managed by home-manager (modules/linux/sshd.nix) -- do not edit by hand.
    PasswordAuthentication no
    PermitRootLogin no
    PubkeyAuthentication yes
    EOF

    if ! sudo cmp -s "$DROPIN_TMP" "$DROPIN_PATH" 2>/dev/null; then
      BACKUP_PATH="$DROPIN_PATH.bak-pre-nix"
      if sudo test -f "$DROPIN_PATH"; then
        sudo cp -p "$DROPIN_PATH" "$BACKUP_PATH"
      fi

      $DRY_RUN_CMD sudo install -m 644 -o root -g root "$DROPIN_TMP" "$DROPIN_PATH"

      if sudo sshd -t; then
        $DRY_RUN_CMD sudo systemctl reload ssh
        sudo rm -f "$BACKUP_PATH"
      else
        echo "sshd config test FAILED after installing $DROPIN_PATH -- rolling back" >&2
        if sudo test -f "$BACKUP_PATH"; then
          sudo mv "$BACKUP_PATH" "$DROPIN_PATH"
        else
          sudo rm -f "$DROPIN_PATH"
        fi
        rm -f "$DROPIN_TMP"
        exit 1
      fi
    fi
    rm -f "$DROPIN_TMP"
  '';
}
