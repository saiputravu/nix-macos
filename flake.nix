{
  description = "Nix-darwin system flake";

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
  let hostname = "mahi"; in
  let username = "sai"; in
  let homedir = "/Users/sai"; in
  let
    pkgs-stable = nixpkgs-stable.legacyPackages.aarch64-darwin;
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
      nixpkgs.hostPlatform = "aarch64-darwin";
      
      users.users.sai = {
        name = username;
        home = homedir;
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
    # Build darwin flake using:
    # $ darwin-rebuild build --flake .#simple
    darwinConfigurations."${hostname}" = nix-darwin.lib.darwinSystem {
      specialArgs = { inherit username homedir inputs; };
      modules = [
          configuration
          ./modules/configuration.nix
          ./modules/home-manager.nix
        ];
    };
  };
}
