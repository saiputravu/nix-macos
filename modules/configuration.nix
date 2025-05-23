{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
  ];

  environment = {
    systemPackages = with pkgs; [
      # System wide packages
      # $ nix-env -qaP | grep wget
      wget
      vim
      neovim
      tmux
      go
      tree-sitter
      nodejs_24
      opam
      aerospace
      ripgrep
      ice-bar
      nixd
      neofetch
      btop
      htop
    ];
  };


  security = {
    pam.services.sudo_local = {
      touchIdAuth = true;
      reattach = true; # For tmux etc.
    };
  };

  services = {
    aerospace = {
      enable = true;
      settings = pkgs.lib.importTOML ../configs/aerospace.toml;
    };
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
        InitialKeyRepeat = 15;
        KeyRepeat = 1;

        AppleFontSmoothing = 2;
        
        NSAutomaticSpellingCorrectionEnabled = false;
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;

        AppleInterfaceStyle = "Dark";

        "com.apple.mouse.tapBehavior" = 1;
        "com.apple.trackpad.enableSecondaryClick" = false;
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

        wvous-bl-corner = 1; # bottom left
        wvous-br-corner = 14;
        wvous-tl-corner = 1;
        wvous-tr-corner = 1;
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
  };
}
