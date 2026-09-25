# The 07:00 message: what's on the calendar, what the plan says, what slipped.
# notes.txt item 7, calendar half.
#
# Nothing here computes anything the vault already computes. `plan_day.py` knows
# the day's blocks and which of them are still open, and `calendar_pull.py` is
# read-only by construction -- its allow-list refuses any gcalcli subcommand
# that is not `agenda` or `list` -- and already flags events that collide with
# the study blocks. This module is the thing that runs them at a fixed hour and
# puts the result on the phone through ntfy.
#
# The script prints to stdout and knows nothing about ntfy: running
# `morning-digest` by hand has to stay useful, and it is what you reach for when
# the timer's output looks wrong.
#
# Google Calendar is a manual step -- see the gcalcli line in the README. Until
# `gcalcli init` has run, the calendar sections degrade to a one-line notice and
# the rest of the digest still arrives.
{
  config,
  pkgs,
  lib,
  ...
}: let
  vault = import ./lib/vault.nix {inherit pkgs;};

  digest = pkgs.writeShellApplication {
    name = "morning-digest";
    runtimeInputs = [pkgs.gcalcli pkgs.coreutils] ++ vault.runtimeInputs;
    text = ''
      # Every section is best-effort. A digest missing its calendar half is far
      # more useful at 07:00 than no digest at all, so a section that fails says
      # so and the next one still runs.
      section() {
        printf '\n== %s ==\n' "$1"
      }

      # Asked to run unauthenticated, gcalcli starts an interactive auth flow
      # and, with no stdin, dies on EOF with a 20-line traceback -- which would
      # be the first thing in the push notification. Check for the token it
      # writes instead. XDG data dir, with the pre-4.x path as a fallback.
      gcal_ready() {
        [ -e "''${XDG_DATA_HOME:-$HOME/.local/share}/gcalcli/oauth" ] ||
          [ -e "$HOME/.gcalcli_oauth" ]
      }

      today="$(date +%Y-%m-%d)"
      # gcalcli's end is exclusive, so +2 days is today and tomorrow.
      through="$(date -d '+2 days' +%Y-%m-%d)"

      section "Calendar, today and tomorrow"
      if gcal_ready; then
        gcalcli --nocolor agenda "$today" "$through" 2>&1 || echo "(gcalcli failed)"
      else
        echo "(no calendar -- run 'gcalcli init' once on this box)"
      fi

      cd ${vault.root}
      ${vault.env}

      section "Today"
      uv run scripts/plan_day.py 2>&1 || echo "(plan unavailable)"

      section "Still open from yesterday"
      uv run scripts/plan_day.py --yesterday 2>&1 || echo "(plan unavailable)"

      # calendar_pull.py shells out to gcalcli too, so it needs the same gate.
      section "Collisions with the study blocks"
      if gcal_ready; then
        uv run scripts/calendar_pull.py --days 2 2>&1 || echo "(calendar unavailable)"
      else
        echo "(no calendar)"
      fi
    '';
  };

  push = pkgs.writeShellScript "morning-digest-push" ''
    set -euo pipefail
    ${lib.getExe digest} | notify -t "Morning digest"
  '';
in {
  # gcalcli is here for the one-time `gcalcli init`, not only for the timer.
  home.packages = [digest pkgs.gcalcli];

  systemd.user.services.morning-digest = {
    Unit = {
      Description = "Morning digest: calendar, today's plan, what is still open";
      After = ["network-online.target"];
      Wants = ["network-online.target"];
      RequiresMountsFor = [vault.root];
      OnFailure = ["notify-failure@%n.service"];
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${push}";
      # notify lives in the user profile, not in a store path this unit knows --
      # same reason vault-sync.nix's failure handler sets PATH.
      Environment = ["PATH=%h/.nix-profile/bin:/usr/bin:/bin"];
    };
  };

  systemd.user.timers.morning-digest = {
    Unit.Description = "Morning digest at 07:00";
    Timer = {
      OnCalendar = "*-*-* 07:00:00";
      # A box that was off at 07:00 still owes me the digest when it comes back.
      Persistent = true;
    };
    Install.WantedBy = ["timers.target"];
  };
}
