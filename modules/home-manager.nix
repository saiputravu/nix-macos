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

  imports = [
      inputs.spicetify-nix.homeManagerModules.default
  ];

  home = 
  let steam-package = pkgs.callPackage ./steam.nix {}; in
  {
    stateVersion = "23.05";

    username = username;
    homeDirectory = homedir;

    packages = with pkgs; [
      # Local apps
      # $ nix-env -qaP | grep wget

      # General GUI apps
      google-chrome
      anki-bin
      discord
      zathura
      obsidian

      spotify-unwrapped
      spicetify-cli

      colima
      docker
      vscode

      steam-package
    ];

    sessionVariables = {
      EDITOR = "nvim";
    };

    file = {
      ".zshrc".source = ../configs/zshrc;
    };
  };

  programs = {
    htop = {
        enable = true;
        settings.show_program_path = true;
    };
    git = {
      enable = true;
      userName = "${username}";
      ignores = [".DS_STORE"];
      extraConfig = {
        init.defaultBranch = "main";
        push.autoSetupRemote = true;
      };
    };
    spicetify =
    let 
      spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.system};
    in
    {
      enable = true;
      theme = spicePkgs.themes.ziro;
      colorScheme = "red-dark";
      enabledExtensions = with spicePkgs.extensions; [
        keyboardShortcut
        shuffle
      ];
    };
    tmux = {
      enable = true;
      extraConfig = builtins.readFile ../configs/tmux.conf;
    };


    home-manager = {
        enable = true;
    };
  };

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
    users.sai = saiHomeConfig;
    backupFileExtension = "hm-backup";
  };
}
