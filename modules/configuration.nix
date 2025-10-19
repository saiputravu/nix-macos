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
      aerospace
      ripgrep
      nixd
      deadnix
      neofetch
      btop
      htop
      tree
      lua
    ];
  };

  homebrew = {
    enable = true;
    # onActivation.cleanup = "uninstall";
    taps = ["FelixKratz/formulae"];
    brews = [
      "borders"
    ];
    casks = [
      "tailscale-app"
      "ghostty"
      "mac-mouse-fix"
      "orion"
      "folx"
      "gimp"
      "citrix-workspace"
      "webex"
      "altserver"
      "utm"
      "arc"
      "zen"
      "spotify"
      "Sikarugir-App/sikarugir/sikarugir"
      "porting-kit"
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
      settings = pkgs.lib.importTOML ../configs/aerospace/aerospace.toml;
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
    hostName = "mahi";
    computerName = "Mahi";
  };

  fonts = {
    packages = [
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
      CustomUserPreferences.NSGlobalDomain = {
        "com.apple.sound.uiaudio.enabled" = false;
      };
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

        _HIHideMenuBar = false; 
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
