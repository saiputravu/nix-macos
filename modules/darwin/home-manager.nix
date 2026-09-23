# Wires home-manager into nix-darwin. The actual home config lives in
# ../common/home.nix (shared) and ./home.nix (macOS-only).
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
    inputs.home-manager.darwinModules.home-manager
  ];

  home-manager = {
    extraSpecialArgs = { inherit username homedir inputs; };

    useGlobalPkgs = true;
    useUserPackages = true;
    users.${username} = {
      imports = [
        ../common/home.nix
        ./home.nix
      ];
    };
    backupFileExtension = "hm-backup";
  };
}
