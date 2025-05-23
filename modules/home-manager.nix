{
  config,
  pkgs,
  lib,
  username,
  homedir,
  inputs,
  ...
}:
let saiHomeConfig = {
  pkgs,
  lib,
  config,
  inputs,
  username,
  homedir,
  ...
}: {
  home = {
    stateVersion = "23.05";

    username = username;
    homeDirectory = homedir;

    packages = with pkgs; [
      # Local apps
      # $ nix-env -qaP | grep wget

      # General GUI apps
      anki-bin
      discord
      vscode
      zathura
    ];

    sessionVariables = {
      EDITOR = "nvim";
    };

    file = {
      ".zshrc" = ../configs/zshrc
    };
  };

  programs = {
    htop = {
        enable = true;
        settings.show_program_path = true;
    };
  };

  programs.home-manager.enable = true;
};
in
{
  imports = [
    inputs.home-manager.darwinModules.home-manager
  ];

  home-manager = {
    extraSpecialArgs = { inherit username homedir inputs; };

    useGlobalPkgs = true;
    useUserPackages = true;
    verbose = true;
    users.sai = saiHomeConfig;
  };
}
