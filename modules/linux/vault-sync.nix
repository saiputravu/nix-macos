# The Obsidian vault's non-LiveSync halves: git history, and draining _inbox.
#
# The vault at /srv/storage/repos/notes has been synced by the obsidian-git
# *plugin* until now. Its own .gitignore records why that has to stop once
# LiveSync is in play:
#
#   "sharing obsidian-git's config across machines means every device must run
#    the same push behaviour, which is what let a stale phone commit-and-sync
#    revert a desktop session"
#
# So the roles split cleanly: LiveSync is the transport between devices, and
# git is history -- written by exactly one writer, this box, on a timer. Remove
# obsidian-git from .obsidian/community-plugins.json on every device.
#
# The second timer exists because LiveSync changes what `_inbox/` is. Today the
# .gitignore excludes `_inbox/*`, so iPad captures never reach this machine at
# all; once they replicate, `ingest.py` can recover their text automatically.
# Originals are then archived out of the vault, which is what keeps both the
# repo and CouchDB's chunk store from growing without bound.
{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (import ./lib/vault.nix {inherit pkgs;}) root env runtimeInputs;

  vault = root;
  archive = "/srv/storage/archive/inbox";

  # Originals are only archived once their sidecar exists *and* they have sat
  # still for a week -- long enough that something dropped in today and still
  # being worked on is never pulled out from under you.
  archiveAfterDays = 7;

  vaultGit = pkgs.writeShellApplication {
    name = "vault-git";
    runtimeInputs = [pkgs.git pkgs.git-lfs pkgs.openssh];
    text = ''
      cd ${vault}

      # The repo has git-lfs hooks installed; they exit 2 if git-lfs is not on
      # PATH, which a systemd user unit would not otherwise provide.
      if [ -z "$(git status --porcelain)" ]; then
        exit 0
      fi

      git add -A
      git commit -m "sync: $(date -Iseconds)"

      # The push key has no passphrase, so no agent is needed -- but the unit
      # has no SSH_AUTH_SOCK either, hence naming the identity explicitly.
      GIT_SSH_COMMAND="ssh -i $HOME/.ssh/id_ed25519 -o IdentitiesOnly=yes" \
        git push
    '';
  };

  vaultIngest = pkgs.writeShellApplication {
    name = "vault-ingest";
    runtimeInputs = runtimeInputs ++ [pkgs.coreutils pkgs.findutils];
    text = ''
      cd ${vault}
      ${env}

      uv run scripts/ingest.py

      # Archive originals whose text has already been recovered. ingest.py
      # skips any item that already has a sidecar in _inbox/.text/, so removing
      # the original is idempotent: it simply stops being seen.
      find _inbox -mindepth 1 -maxdepth 1 -type f -mtime +${toString archiveAfterDays} \
        -print0 |
        while IFS= read -r -d ''' original; do
          base="$(basename "$original")"
          if [ -e "_inbox/.text/''${base}.md" ]; then
            dest=${archive}/"$(date +%Y)"
            mkdir -p "$dest"
            mv -n "$original" "$dest/"
          fi
        done
    '';
  };
in {
  home.packages = [vaultGit vaultIngest];

  home.activation.vaultArchiveDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

    if [ ! -d "${archive}" ]; then
      $DRY_RUN_CMD sudo mkdir -p "${archive}"
      $DRY_RUN_CMD sudo chown "$USER":"$USER" "${archive}"
    fi
  '';

  systemd.user.services.vault-git = {
    Unit = {
      Description = "Commit and push the Obsidian vault";
      After = ["network-online.target"];
      Wants = ["network-online.target"];
      RequiresMountsFor = [vault];
      # A vault that has stopped reaching GitHub is worth hearing about.
      OnFailure = ["notify-failure@%n.service"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${lib.getExe vaultGit}";
    };
  };

  systemd.user.timers.vault-git = {
    Unit.Description = "Hourly vault commit";
    Timer = {
      OnCalendar = "hourly";
      # Catch up after the box has been asleep.
      Persistent = true;
      RandomizedDelaySec = "5m";
    };
    Install.WantedBy = ["timers.target"];
  };

  systemd.user.services.vault-ingest = {
    Unit = {
      Description = "Recover text from new vault captures and archive originals";
      RequiresMountsFor = [vault];
      OnFailure = ["notify-failure@%n.service"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${lib.getExe vaultIngest}";
    };
  };

  systemd.user.timers.vault-ingest = {
    Unit.Description = "Vault inbox ingest";
    Timer = {
      OnCalendar = "*-*-* 06,18:30:00";
      Persistent = true;
    };
    Install.WantedBy = ["timers.target"];
  };

  # Shared failure handler: any unit above can say OnFailure=notify-failure@%n.
  systemd.user.services."notify-failure@" = {
    Unit.Description = "Push a failure notification for %i";
    Service = {
      Type = "oneshot";
      ExecStart = let
        report = pkgs.writeShellScript "notify-failure" ''
          set -eu
          unit="$1"
          notify -t "maui: $unit failed" -p high \
            "$(${pkgs.systemd}/bin/journalctl --user -u "$unit" -n 20 --no-pager 2>/dev/null || echo 'no journal output')"
        '';
      in "${report} %i";
      # notify lives in the user profile, not in a store path this unit knows.
      Environment = ["PATH=%h/.nix-profile/bin:/usr/bin:/bin"];
    };
  };
}
