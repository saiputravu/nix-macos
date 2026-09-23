# Linux-only home-manager config (maui, Debian 13 trixie).
#
# Debian is not NixOS, so there is no system-level module here: this is applied
# with standalone home-manager and only ever touches $HOME. System packages
# (zsh, curl, build-essential, ...) stay apt's job -- see README.
{
  config,
  pkgs,
  lib,
  username,
  homedir,
  inputs,
  ...
}: {
  imports = [
    ./tailscale.nix
    ./sshd.nix
    ./sudo-ssh-agent-auth.nix
  ];

  # Non-NixOS glue: fixes XDG_DATA_DIRS, the locale archive, and .desktop/icon
  # lookup so nix-installed programs behave on Debian.
  targets.genericLinux.enable = true;

  # NOTE: allowUnfree is set on the pkgs instance in flake.nix -- standalone
  # home-manager gets no useGlobalPkgs to inherit it from.

  home = {
    stateVersion = "25.05";

    packages = with pkgs; [
      # Shared baseline (helix, zellij, delta) comes from ../common/home.nix.
      ripgrep
      gh

      # ai
      inputs.claude-code-nix.packages.${pkgs.system}.default
    ];

    file = {
      # Linux-only dotfiles go here.
    };
  };

  # Things to pull across from ../darwin/home.nix as this box gets used:
  #
  #   fonts.fontconfig.enable = true;          # needed before any GUI app
  #   home.packages = with pkgs; [
  #     ghostty                                # linux build exists; config in configs/ghostty
  #     rustc cargo rustfmt rust-analyzer lspmux
  #     go gopls golangci-lint
  #     uv python3Packages.jedi-language-server
  #     inputs.claude-code-nix.packages.${pkgs.system}.default
  #     xclip                                  # configs/tmux.conf pipes copy to it
  #   ];
}
