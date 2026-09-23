# Cross-platform home-manager config. Imported by both the darwin wrapper
# (modules/darwin/home-manager.nix) and the standalone linux config
# (homeConfigurations."sai@maui" in flake.nix).
{
  config,
  pkgs,
  lib,
  username,
  homedir,
  inputs,
  ...
}: {
  home = {
    # Linux overrides this in modules/linux/home.nix.
    stateVersion = lib.mkDefault "23.05";

    username = username;
    homeDirectory = homedir;

    packages = with pkgs; [
      helix
      zellij
      delta # configs/gitconfig hardcodes `pager = delta`
      just # runs the justfile at the repo root
    ];

    sessionVariables = {
      # Darwin overrides this to nvim.
      EDITOR = lib.mkDefault "hx";
    };

    file = {
      # z4h's self-bootstrapping loader. Without it .zshrc dies on `z4h: command not found`.
      ".zshenv".source = ../../configs/zshenv;
      ".zshrc".source = ../../configs/zshrc;
      ".gitconfig".source = ../../configs/gitconfig;
      ".config/helix/config.toml".source = ../../configs/helix/config.toml;
      ".config/helix/languages.toml".source = ../../configs/helix/languages.toml;
      ".config/zellij" = {
        source = ../../configs/zellij;
        recursive = true;
      };
    };
  };

  programs = {
    htop = {
      enable = true;
      settings.show_program_path = true;
    };
    git = {
      enable = true;
      ignores = [".DS_STORE"];
      lfs.enable = true;
      signing.format = "openpgp";
      settings = {
        user.name = "${username}";
        init.defaultBranch = "main";
        push.autoSetupRemote = true;
      };
    };
    tmux = {
      enable = true;
      extraConfig = builtins.readFile ../../configs/tmux.conf;
    };

    home-manager = {
      enable = true;
    };
  };
}
