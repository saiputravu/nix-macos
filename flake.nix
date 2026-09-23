{
  description = "Personal nix config: macOS (nix-darwin) + Debian (standalone home-manager)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixpkgs-24.11-darwin";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-code-nix.url = "github:sadjow/claude-code-nix";
    # Spotify skinning
    # spicetify-nix.url = "github:Gerg-L/spicetify-nix";
  };

  outputs = inputs@{
    self,
    nix-darwin,
    nixpkgs,
    nixpkgs-stable,
    home-manager,
    claude-code-nix,
    # spicetify-nix
  }:
  let
    hosts = {
      # macOS laptop, managed by nix-darwin (system + home).
      mahi = {
        system = "aarch64-darwin";
        username = "sai";
        homedir = "/Users/sai";
      };
      # Debian 13 trixie, managed by standalone home-manager ($HOME only).
      maui = {
        system = "x86_64-linux";
        username = "sai";
        homedir = "/home/sai";
      };
      noble2 = {
        system = "x86_64-linux";
        username = "root";
        homedir = "/root";
      };
    };
  in
  let
    # Darwin-only: used by the zathura pin below. Do not reference from anything shared.
    pkgs-stable = nixpkgs-stable.legacyPackages.${hosts.mahi.system};
  in
  let
    configuration = { pkgs, ... }: {
      # Necessary for using flakes on this system.
      nix.settings.experimental-features = "nix-command flakes";
      nixpkgs.config.allowUnfree = true;

      # Set Git commit hash for darwin-version.
      system.configurationRevision = self.rev or self.dirtyRev or null;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 6;

      # The platform the configuration will be used on.
      nixpkgs.hostPlatform = hosts.mahi.system;

      users.users.${hosts.mahi.username} = {
        name = hosts.mahi.username;
        home = hosts.mahi.homedir;
      };

      nixpkgs.overlays = [
        (self: super: {
          libsForQt5 = super.libsForQt5 // {
            fcitx5-with-addons = super.fcitx5;
          };
          # Use stable zathura to avoid broken appstream 1.1.2 darwin build
          inherit (pkgs-stable) zathura;
        })
      ];
    };
  in
  {
    # macOS:
    # $ sudo darwin-rebuild switch --flake .#mahi
    darwinConfigurations.mahi = nix-darwin.lib.darwinSystem {
      specialArgs = {
        inherit inputs;
        inherit (hosts.mahi) username homedir;
      };
      modules = [
          configuration
          ./modules/darwin/configuration.nix
          ./modules/darwin/home-manager.nix
        ];
    };

    # Debian (non-NixOS, so home-manager runs standalone):
    # $ home-manager switch -b backup --flake .#sai@maui
    homeConfigurations."${hosts.maui.username}@maui" = home-manager.lib.homeManagerConfiguration {
      # No useGlobalPkgs here, so allowUnfree has to be set on this pkgs instance.
      pkgs = import nixpkgs {
        inherit (hosts.maui) system;
        config.allowUnfree = true;
      };
      extraSpecialArgs = {
        inherit inputs;
        inherit (hosts.maui) username homedir;
      };
      modules = [
        ./modules/common/home.nix
        ./modules/linux/home.nix
      ];
    };

    homeConfigurations."${hosts.noble2.username}@noble2" = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs {
        inherit (hosts.noble2) system;
        config.allowUnfree = true;
      };
      extraSpecialArgs = {
        inherit inputs;
        inherit (hosts.noble2) username homedir;
      };
      modules = [
        ./modules/common/home.nix
        ./modules/linux/home.nix
      ];
    };
  };
}
