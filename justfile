# Task runner for this nix config. Recipes dispatch on the host OS:
# macOS -> nix-darwin (system + home), Linux -> standalone home-manager ($HOME).
#
#   just            list recipes
#   just switch     apply the config for this host
#   just dry        show what a switch would change, without applying

flake := justfile_directory()
host := `hostname -s`

# List available recipes.
default:
    @just --list --unsorted

# Build this host's config without activating it. Result symlink: ./result
[group('build')]
build:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "$(uname)" == Darwin ]]; then
      darwin-rebuild build --flake '{{ flake }}#{{ host }}'
    else
      nix build --out-link '{{ flake }}/result' \
        '{{ flake }}#homeConfigurations."'"$USER"'@{{ host }}".activationPackage'
    fi

# Resolve the full build plan without building or downloading anything.
[group('build')]
plan:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "$(uname)" == Darwin ]]; then
      nix build --dry-run '{{ flake }}#darwinConfigurations.{{ host }}.system'
    else
      nix build --dry-run \
        '{{ flake }}#homeConfigurations."'"$USER"'@{{ host }}".activationPackage'
    fi

# Build, then diff the result against what is currently live. Changes nothing.
[group('build')]
dry: build
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "$(uname)" == Darwin ]]; then
      nix store diff-closures /run/current-system '{{ flake }}/result'
    else
      nix store diff-closures ~/.local/state/nix/profiles/home-manager '{{ flake }}/result' \
        2>/dev/null || echo "no existing home-manager generation to diff against"
    fi

# Apply this host's config.
[group('apply')]
switch:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "$(uname)" == Darwin ]]; then
      sudo darwin-rebuild switch --flake '{{ flake }}#{{ host }}'
    else
      home-manager switch -b backup --flake '{{ flake }}#'"$USER"'@{{ host }}'
    fi

# First-ever activation on a Linux box, before home-manager is on PATH.
[group('apply')]
bootstrap-linux:
    nix run home-manager/master -- switch -b backup \
      --flake '{{ flake }}#'"$USER"'@{{ host }}'

# Roll back to the previous generation.
[group('apply')]
rollback:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "$(uname)" == Darwin ]]; then
      sudo darwin-rebuild rollback
    else
      # home-manager has no rollback subcommand: re-activate the previous generation.
      prev=$(home-manager generations | sed -n 2p | grep -o '/nix/store/[^ ]*')
      echo "re-activating $prev"
      "$prev"/activate
    fi

# Evaluate BOTH hosts' configs. Catches module errors without needing a builder.
[group('check')]
check:
    @echo "-> mahi   (aarch64-darwin)"
    @nix eval --raw '{{ flake }}#darwinConfigurations.mahi.system.drvPath'
    @echo
    @echo "-> sai@maui (x86_64-linux)"
    @nix eval --raw '{{ flake }}#homeConfigurations."sai@maui".activationPackage.drvPath'
    @echo
    @echo "-> root@noble2 (x86_64-linux)"
    @nix eval --raw '{{ flake }}#homeConfigurations."root@noble2".activationPackage.drvPath'
    @echo

# List generations for this host.
[group('check')]
generations:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "$(uname)" == Darwin ]]; then
      darwin-rebuild --list-generations
    else
      home-manager generations
    fi

# Update every flake input.
[group('update')]
update:
    nix flake update --flake '{{ flake }}'

# Update a single flake input, e.g. `just update-input nixpkgs`.
[group('update')]
update-input input:
    nix flake update '{{ input }}' --flake '{{ flake }}'

# Delete old generations and collect garbage. Destructive: keeps only the current one.
[group('update')]
gc:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "$(uname)" == Darwin ]]; then
      sudo nix-collect-garbage -d
    else
      home-manager expire-generations '-7 days'
    fi
    nix store gc
