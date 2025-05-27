{ pkgs ? import <nixpkgs> {} }:

let
  # --- User-configurable values ---
  appName = "Orion"; # The name of the .app bundle, e.g., "VLC.app"
  pname = "orion"; # Lowercase package name
  version = "1.0.0";       # Version of the application

  # URL for the DMG file
  dmgUrl = "https://cdn.kagi.com/downloads/15_0/Orion.dmg";

  # SHA256 hash of the DMG file.
  # You can get this by first trying a fake hash (e.g., lib.fakeSha256),
  # letting the build fail, and Nix will tell you the expected hash.
  # Or use: nix-prefetch-url --type sha256 ${dmgUrl}
  dmgSha256 = "sha256-UXB5sOy5QDGErtiDYz6XEn88ewBs8PKC6w4F5dYzK4A=";

  # Optional: If the .app bundle inside the DMG is in a subdirectory
  # e.g., if after mounting, the path is ./mountpoint/SubDir/YourAppName.app
  # then appPathInDmg = "SubDir/${appName}.app";
  # If it's at the root of the DMG, it's just "${appName}.app"
  appPathInDmg = "${appName}.app";

in
pkgs.stdenv.mkDerivation {
  inherit pname version;

  src = pkgs.fetchurl {
    url = dmgUrl;
    sha256 = dmgSha256;
    name = "${pname}-${version}.dmg"; # Optional: helps with clarity in /nix/store
  };

  # Tools needed during the build process on Darwin
  nativeBuildInputs = [
    pkgs.undmg # Utility to extract DMG contents (preferred)
  ];

  # If undmg creates a subdirectory, you might need to set sourceRoot.
  # For example, if undmg extracts to a folder named after the DMG:
  # sourceRoot = "."; # Default, assuming undmg extracts app to the top level of $TMPDIR/
                      # Or if undmg -x extracts to a specific folder like YourAppName.app

  installPhase = ''
    runHook preInstall

    # Create the target directory structure
    # macOS convention is to place .app bundles in /Applications
    # In Nix, we place them in $out/Applications/
    mkdir -p $out/Applications

    # undmg might extract the .app bundle directly.
    # You'll need to check how undmg behaves with your specific DMG.
    # It might extract the whole DMG content or just the .app.
    echo "Extracting DMG with undmg..."
    undmg "$src" # This will extract contents to the current directory ($TMPDIR/build)
    rm Applications # Random ass symlink made idk why.

    # Find the extracted .app bundle.
    # The exact path will depend on the DMG structure and how undmg extracts it.
    # It might be directly in the current directory, or in a subdirectory.
    extracted_app_path=$(find . -maxdepth 2 -name "${appPathInDmg}" -type d -print -quit)

    if [ -z "$extracted_app_path" ]; then
      echo "Error: Could not find ${appPathInDmg} after extracting DMG."
      ls -R . # List contents for debugging
      exit 1
    fi

    echo "Found app at $extracted_app_path"
    cp -R "$extracted_app_path" "$out/Applications/${appName}.app"

    runHook postInstall
  '';

  # Metadata about the package
  meta = with pkgs.lib; {
    description = "Custom build for ${appName}";
    license = licenses.unfree; # Or whatever the actual license is
    platforms = platforms.darwin;
  };
}
