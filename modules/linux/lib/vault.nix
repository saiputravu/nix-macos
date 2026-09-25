# The Obsidian vault, and the environment its scripts expect.
#
# The vault carries its own flake, and every script in it declares its
# dependencies with PEP 723 inline metadata and is run with `uv run`. That works
# because the flake's shellHook pins three variables first. Timers cannot use
# `nix develop` -- it wants the network on every run -- so they export the same
# three and call `uv run` directly.
#
# Kept here rather than in each module because two of them need it (vault-sync
# and digest) and the vault path drifting between them would be silent.
{pkgs}: rec {
  root = "/srv/storage/repos/notes";

  # UV_PYTHON matters more than it looks: without it uv falls back to whatever
  # python is on PATH, and the vault's sqlite-vector scripts need an interpreter
  # built with enable_load_extension.
  env = ''
    export VAULT_ROOT=${root}
    export UV_PYTHON=${pkgs.python312}/bin/python3.12
    export UV_PYTHON_DOWNLOADS=never
    export UV_CACHE_DIR=${root}/.uv-cache
  '';

  # What a writeShellApplication running those scripts needs on PATH.
  runtimeInputs = [pkgs.uv pkgs.python312];
}
