{
  description = "Nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager }:
  let
    configuration = { pkgs, ... }: {
      # List packages installed in system profile. To search by name, run:
      # $ nix-env -qaP | grep wget
      environment.systemPackages =
        [ pkgs.vim
          pkgs.wget
          pkgs.tmux
          pkgs.go
          pkgs.tree-sitter
          pkgs.nodejs_24
          pkgs.opam
          pkgs.aerospace
          pkgs.zathura
          pkgs.anki-bin
          pkgs.discord
          pkgs.ripgrep
          pkgs.vscode
          pkgs.ice-bar
          pkgs.aerospace
        ];

      # Necessary for using flakes on this system.
      nix.settings.experimental-features = "nix-command flakes";
      nixpkgs.config.allowUnfree = true;

      # Set Git commit hash for darwin-version.
      system.configurationRevision = self.rev or self.dirtyRev or null;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 6;

      # The platform the configuration will be used on.
      nixpkgs.hostPlatform = "aarch64-darwin";
      
    };
    homeconfig = {pkgs, ...}: {
      # Internal compatibility configuration for home-manager, do not change this.
      home.stateVersion = "23.05";

      # Letting home-manager install and manage itself
      programs.home-manager.enable = true;
      home.packages = with pkgs; [];

      home.sessionVariables = {
        EDITOR = "nvim";
      };
    };
  in
  {
    # Build darwin flake using:
    # $ darwin-rebuild build --flake .#simple
    darwinConfigurations."sai" = nix-darwin.lib.darwinSystem {
      modules = [
          configuration
          ./modules/configuration.nix
          ./modules/home-manager.nix
        ];
    };
  };
}
