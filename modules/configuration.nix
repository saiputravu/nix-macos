{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    # ./touch-id.nix
  ];

  environment = {
    systemPackages = with pkgs; [
      # 1Password has to be installed system-wide
      # _1password
    ];
  };


  security = {
    pam.services.sudo_local = {
      touchIdAuth = true;
      reattach = true; # For tmux etc.
    };
  };

  services = {
    # nix-daemon.enable = true;
    # aerospace = {
    #   enable = true;
    # };
  };

  # Logging is disabled by default
  programs = {
    zsh = {
      enable = true;
      enableCompletion = false;
      enableBashCompletion = false;
    };
    man.enable = true;
  };

  networking = {
    hostName = "sai";
    computerName = "Sai";
  };

  fonts = {
    packages = with pkgs; [
        # pkgs.nerd-fonts.JetBrainsMono
        pkgs.nerd-fonts._0xproto
        pkgs.nerd-fonts.droid-sans-mono
    ];
  };

  time = {
    timeZone = "Europe/London";
  };

  # https://mynixos.com/nix-darwin/options/system.defaults
  system = {
    primaryUser = "sai";

    defaults = {
      NSGlobalDomain = {
        KeyRepeat = 15;
        InitialKeyRepeat = 1;

        AppleFontSmoothing = 2;
        
        NSAutomaticSpellingCorrectionEnabled = false;
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;

        AppleInterfaceStyle = "Dark";

        "com.apple.mouse.tapBehavior" = 1;
        "com.apple.trackpad.enableSecondaryClick" = false;

        _HIHideMenuBar = true;
      };
      controlcenter = {
          AirDrop = true;
          BatteryShowPercentage = true;
          Bluetooth = true;
          Display = true;
          FocusModes = true;
          NowPlaying = true;
          Sound = true;
      };
      dock = {
        autohide = true;
        autohide-delay = 0.1;
        autohide-time-modifier = 0.1;
        minimize-to-application = true;
        show-recents = false;
        static-only = true;
      };
      finder = {
        AppleShowAllExtensions = true;
        AppleShowAllFiles = true;
        ShowPathbar = true;
        CreateDesktop = false;
        FXRemoveOldTrashItems = true; # Remove items after 30 days from trash
        QuitMenuItem = true; # Allow quitting
      };
      loginwindow = {
        GuestEnabled = false;
        DisableConsoleAccess = true;
        LoginwindowText = "Wassaahhh 👹";
      };
      LaunchServices.LSQuarantine = true;
      spaces.spans-displays = false;
    };

    keyboard = {
      # enableKeyMapping = true;
      # remapCapsLockToEscape = true;
      # swapLeftCommandAndLeftAlt = true;
    };

    # build.applications = pkgs.lib.mkForce (pkgs.buildEnv {
    #   name = "applications";
    #   # link home-manager apps into /Applications instead of ~/Applications
    #   # fix from https://github.com/LnL7/nix-darwin/issues/139#issuecomment-663117229
    #   paths = config.environment.systemPackages ++ config.home-manager.users.${config.user}.home.packages;
    #   pathsToLink = "/Applications";
    # });

    # https://github.com/zhaofengli/nix-homebrew/issues/3#issuecomment-1622240992
    # activationScripts = {
    #   extraUserActivation.text = lib.mkOrder 1501 (lib.concatStringsSep "\n" (lib.mapAttrsToList (prefix: d:
    #     if d.enable
    #     then ''
    #       sudo chown -R ${config.nix-homebrew.user} ${prefix}/bin
    #       sudo chgrp -R ${config.nix-homebrew.group} ${prefix}/bin
    #     ''
    #     else "")
    #   config.nix-homebrew.prefixes));
    #   postActivation.text = ''
    #     ${pkgs.skhd}/bin/skhd -r
    #   '';
    # };
  };

  # security.pam.enableSudoTouchId = true;
}
