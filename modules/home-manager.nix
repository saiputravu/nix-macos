{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
  ];

  home-manager = {
    darwinModules.home-manager = {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.verbose = true;
      home-manager.users.$USER = homeconfig;
    };
  };
}
