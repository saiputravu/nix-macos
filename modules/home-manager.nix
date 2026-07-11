{
  config,
  pkgs,
  lib,
  username,
  homedir,
  inputs,
  ...
}:
let saiHomeConfig = {
  pkgs,
  lib,
  config,
  inputs,
  username,
  homedir,
  ...
}:
let
  claudePkg = inputs.claude-code-nix.packages.${pkgs.system}.default;
  sioyekPy = pkgs.python3Packages.buildPythonPackage rec {
    pname = "sioyek";
    version = "0.31.11";
    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "1qsbpnmr5jyla77wbs7hrpxvcp5sr36rxbb49wmwsls2dlmz0fib";
    };
    doCheck = false;
  };
  pythonEnv = pkgs.python3.withPackages (_: [ sioyekPy ]);
  sioyekScriptStore = pkgs.writeText "sioyek_claude_session.py"
    (builtins.readFile ../configs/sioyek/sioyek_claude_session.py);
  sioyekClaude = pkgs.writeShellScriptBin "sioyek-claude-session" ''
    export PATH="${claudePkg}/bin:$PATH"
    exec ${pythonEnv}/bin/python3 ${sioyekScriptStore} "$@"
  '';
in {

  imports = [
      # inputs.spicetify-nix.homeManagerModules.default
  ];

  home = 
  let steam-package = pkgs.callPackage ./steam.nix {}; in
  {
    stateVersion = "23.05";

    username = username;
    homeDirectory = homedir;

    packages = with pkgs; [
      # Local apps
      # $ nix-env -qaP | grep wget

      # General GUI apps
      anki-bin
      discord
      zathura
      sioyek
      obsidian
      ice-bar
      github-cli
      pkgs.git-xet
      marksman
      dprint

      # ai
      inputs.claude-code-nix.packages.${pkgs.system}.default
      ngrok

      # SQL
      postgresql

      # inotify
      fswatch

      # spicetify-cli

      google-cloud-sdk
      colima
      docker
      vscode
      rustscan # fast rust nmap scanner

      # Rust deps
      rustc
      cargo
      rustfmt
      rust-analyzer
      rustPackages.clippy

      # Golang deps
      gopls
      go
      golangci-lint
      golangci-lint-langserver
      protobuf
      protoc-gen-go

      # Editors
      helix
      tectonic

      # Git
      delta

      # Python deps
      uv
      python3Packages.jedi-language-server
      python3Packages.jedi
      python3Packages.anthropic
      sioyekClaude

      # Ocaml deps
      ocaml
      opam
      dune_3
      ocamlPackages.ocamlformat

      # Cpp deps
      cmake
      bear

      # Minecraft deps
      prismlauncher

      # Gaming deps
      steam-package
      undmg # Testing any issues with DMG installs.
    ];

    sessionVariables = {
      EDITOR = "nvim";
    };

    file = {
      ".zshrc".source = ../configs/zshrc;
      ".gitconfig".source = ../configs/gitconfig;
      ".config/helix/config.toml".source = ../configs/helix/config.toml;
      ".config/helix/languages.toml".source = ../configs/helix/languages.toml;
      ".config/ghostty" = {
        source = ../configs/ghostty;
        recursive = true;
      };
      ".config/aerospace" = {
        source = ../configs/aerospace;
        recursive = true;
      };
      ".config/zathura" = {
        source = ../configs/zathura;
        recursive = true;
      };
      ".config/sioyek/keys_user.config".source = ../configs/sioyek/keys_user.config;
      ".config/sioyek/prefs_user.config".text =
        (builtins.readFile ../configs/sioyek/prefs_user.config) +
        "new_command _claude4_session ${sioyekClaude}/bin/sioyek-claude-session \"%{sioyek_path}\" \"%{selected_text}\" \"%{document_path}\"\n";
      ".config/zellij" = {
        source = ../configs/zellij;
        recursive = true;
      };
    };

    # activation.forceSpicetifyReapply = lib.hm.dag.entryAfter ["writeBoundary"] ''
    #   echo "INFO: Forcing Spicetify reapplication on every Home Manager activation..."
    #
    #   # Ensure paths are set up for the command if not inheriting them fully
    #   export PATH="${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:$PATH"
    #
    #   # The config file is managed by the programs.spicetify module
    #   # and should contain the correct spotify_path due to 'spotifyApp' setting.
    #   SPICETIFY_CONFIG_PATH="${config.xdg.configHome}/spicetify/config-xpui.ini"
    #
    #   if [ ! -f "$SPICETIFY_CONFIG_PATH" ]; then
    #     echo "ERROR: Spicetify config file not found at $SPICETIFY_CONFIG_PATH. Skipping reapplication." >&2
    #     exit 0 # Or exit 1 if you prefer to halt activation on this failure
    #   fi
    #
    #   echo "INFO: Using Spicetify config: $SPICETIFY_CONFIG_PATH"
    #   echo "INFO: Attempting 'spicetify backup apply'..."
    #
    #   # Attempt to apply Spicetify
    #   # The -q flag makes it quieter on success
    #   if ${pkgs.spicetify-cli}/bin/spicetify -c "$SPICETIFY_CONFIG_PATH" -q backup apply; then
    #     echo "INFO: Spicetify 'backup apply' succeeded."
    #   else
    #     # If 'backup apply' fails, it might have printed errors.
    #     # You could add more detailed error handling or retry logic if needed.
    #     echo "ERROR: Spicetify 'backup apply' failed. Your Spotify theme might not be applied correctly." >&2
    #     echo "INFO: You might need to run 'spicetify apply' manually or check Spotify/Spicetify permissions and paths."
    #   fi
    # '';
  };


  programs = {
    htop = {
      enable = true;
      settings.show_program_path = true;
    };
    git = {
      enable = true;
      ignores = [".DS_STORE"];
      lfs.enable = true;
      signing.format = "openpgp";
      settings = {
        user.name = "${username}";
        init.defaultBranch = "main";
        push.autoSetupRemote = true;
      };
    };
    # spicetify =
    # let 
    #   spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.system};
    # in
    # {
    #   enable = true;
    #   theme = spicePkgs.themes.defaultDynamic;
    #   # colorScheme = "red-dark";
    #   enabledExtensions = with spicePkgs.extensions; [
    #     keyboardShortcut
    #     shuffle
    #   ];
    # };
    tmux = {
      enable = true;
      extraConfig = builtins.readFile ../configs/tmux.conf;
    };

    home-manager = {
        enable = true;
    };
  };
};
in
{
  imports = [
    inputs.home-manager.darwinModules.home-manager
  ];

  home-manager = {
    extraSpecialArgs = { inherit username homedir inputs; };

    useGlobalPkgs = true;
    useUserPackages = true;
    users.sai = saiHomeConfig;
    backupFileExtension = "hm-backup";
  };
}
