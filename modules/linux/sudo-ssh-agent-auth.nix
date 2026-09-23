# Passwordless-but-verified sudo on non-NixOS Debian (maui), via a forwarded
# SSH agent (`ssh -A`) instead of a NOPASSWD sudoers entry.
{
  config,
  pkgs,
  lib,
  username,
  homedir,
  ...
}: {
  home.packages = [pkgs.pam_ssh_agent_auth];

  home.activation.sudoSshAgentAuth = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

    PAM_SUDO="/etc/pam.d/sudo"
    PAM_MARKER="# nix-managed: authenticate sudo via forwarded ssh-agent (falls back to password)"
    # allow_user_owned_authorized_keys_file: without it (or a ~/%h path) the module demands
    # the file be root-owned, and refuses a user-owned authorized_keys as "bad ownership".
    PAM_LINE="auth sufficient ${pkgs.pam_ssh_agent_auth}/libexec/pam_ssh_agent_auth.so file=${homedir}/.ssh/authorized_keys allow_user_owned_authorized_keys_file"

    # Re-diffed (not just presence-checked) on every activation: the module path is a
    # versioned nix store path, so a package update needs the line rewritten, not skipped.
    if ! sudo grep -qxF "$PAM_LINE" "$PAM_SUDO" 2>/dev/null; then
      PAM_TMP="$(mktemp)"
      {
        echo "$PAM_MARKER"
        echo "$PAM_LINE"
        sudo cat "$PAM_SUDO" | grep -v "pam_ssh_agent_auth.so" | grep -vxF "$PAM_MARKER"
      } > "$PAM_TMP"
      $DRY_RUN_CMD sudo install -m 644 -o root -g root "$PAM_TMP" "$PAM_SUDO"
      rm -f "$PAM_TMP"
    fi

    SUDOERS_PATH="/etc/sudoers.d/10-nix-managed-ssh-agent-auth"
    SUDOERS_TMP="$(mktemp)"
    echo 'Defaults:${username} env_keep += "SSH_AUTH_SOCK"' > "$SUDOERS_TMP"

    if ! sudo cmp -s "$SUDOERS_TMP" "$SUDOERS_PATH" 2>/dev/null; then
      if sudo visudo -cf "$SUDOERS_TMP"; then
        $DRY_RUN_CMD sudo install -m 0440 -o root -g root "$SUDOERS_TMP" "$SUDOERS_PATH"
      else
        echo "sudoers drop-in failed validation -- not installed" >&2
        rm -f "$SUDOERS_TMP"
        exit 1
      fi
    fi
    rm -f "$SUDOERS_TMP"
  '';
}
