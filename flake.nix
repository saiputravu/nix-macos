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
    # Spotify skinning
    spicetify-nix.url = "github:Gerg-L/spicetify-nix";
  };

  outputs = inputs@{
    self,
    nix-darwin,
    nixpkgs,
    home-manager,
    spicetify-nix
  }:
  let hostname = "mahi"; in
  let username = "sai"; in
  let homedir = "/Users/sai"; in
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
