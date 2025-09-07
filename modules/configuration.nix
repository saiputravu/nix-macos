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
    ];
  };

  homebrew = {
    enable = true;
    onActivation.cleanup = "uninstall";
    taps = ["FelixKratz/formulae"];
    brews = [
      "sketchybar"
      "borders"
    ];
    casks = [
      "ghostty"
      "mac-mouse-fix"
      "orion"
      "tailscale"
      "folx"
      "gimp"
      "citrix-workspace"
      "webex"
      "altserver"
      "utm"
      "font-hack-nerd-font" # Default font for sketchybar
    ];
  };

  # https://nix-darwin.github.io/nix-darwin/manual/index.html
  launchd.user.agents = {
    # Launching sketchybar as a service using launchd, instead of suggested homebrew.
    sketchybar = {
      serviceConfig = {
        Label = "com.felixkratz.sketchybar";
        Program = "/opt/homebrew/bin/sketchybar"; # Abs path for homebrew on silicon macs
        RunAtLoad = true; # Enable at login
        KeepAlive = true; # Restart on crash
        StandardOutPath = "/tmp/sketchybar.out.log";
        StandardErrorPath = "/tmp/sketchybar.err.log";
      };
    };
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

        _HIHideMenuBar = true; # Need for sketchybar
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
