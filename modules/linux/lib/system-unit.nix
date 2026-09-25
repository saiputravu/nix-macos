# Install a root-owned systemd unit from a home-manager activation script.
#
# Debian is not NixOS, so anything that needs root or a privileged port cannot
# be a `systemd.user.service`. The unit text is still built by Nix and its
# ExecStart still points into the store -- only the install step is imperative,
# and it prompts for sudo during `home-manager switch`.
#
# Rewriting is skipped when the installed file already matches, so a no-op
# switch neither reloads systemd nor restarts a healthy service.
{
  pkgs,
  lib,
}: {
  # mkSystemUnit { name = "blocky.service"; text = ''...''; }
  #
  # restart = false for units that must not be bounced on every content change
  # (nothing uses that yet, but tailscaled's cleanup cycle is the kind of thing
  # it exists for).
  mkSystemUnit = {
    name,
    text,
    restart ? true,
  }: let
    unit = pkgs.writeText name text;
  in ''
    export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

    if ! sudo cmp -s "${unit}" "/etc/systemd/system/${name}" 2>/dev/null; then
      $DRY_RUN_CMD sudo install -m 644 -o root -g root "${unit}" "/etc/systemd/system/${name}"
      $DRY_RUN_CMD sudo systemctl daemon-reload
      ${lib.optionalString restart ''$DRY_RUN_CMD sudo systemctl restart "${name}"''}
    fi

    $DRY_RUN_CMD sudo systemctl enable --now "${name}"
  '';

  # Same idea for a file that is not a unit -- sysctl drop-ins, rendered config.
  # `onChange` runs only when the content actually differs.
  mkSystemFile = {
    path,
    text,
    mode ? "644",
    onChange ? "",
  }: let
    src = pkgs.writeText (baseNameOf path) text;
  in ''
    export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

    if ! sudo cmp -s "${src}" "${path}" 2>/dev/null; then
      $DRY_RUN_CMD sudo install -D -m ${mode} -o root -g root "${src}" "${path}"
      ${onChange}
    fi
  '';
}
