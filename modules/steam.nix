{ pkgs ? import <nixpkgs> {} }:

let
  # --- User-configurable values ---
  appName = "Steam"; # The name of the .app bundle, e.g., "VLC.app"
  pname = "steam"; # Lowercase package name
  version = "1.0.1";       # Version of the application

  # URL for the DMG file
  dmgUrl = "https://cdn.fastly.steamstatic.com/client/installer/steam.dmg";

  # SHA256 hash of the DMG file.
  # You can get this by first trying a fake hash (e.g., lib.fakeSha256),
  # letting the build fail, and Nix will tell you the expected hash.
  # Or use: nix-prefetch-url --type sha256 ${dmgUrl}
  dmgSha256 = "sha256-X1VnDJGv02A6ihDYKhedqQdE/KmPAQZkeJHudA6oS6M=";

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
    # Alternatively, for direct hdiutil usage, you might not need extra build inputs
    # if hdiutil is reliably in the stdenv's path, but undmg is more robust.
    # pkgs.coreutils # For cp, mkdir, etc. (usually part of stdenv)
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

    # Option 1: Using undmg (simpler and often preferred)
    # undmg might extract the .app bundle directly.
    # You'll need to check how undmg behaves with your specific DMG.
    # It might extract the whole DMG content or just the .app.
    echo "Extracting DMG with undmg..."
    undmg "$src" # This will extract contents to the current directory ($TMPDIR/build)

    # Find the extracted .app bundle.
    # The exact path will depend on the DMG structure and how undmg extracts it.
    # It might be directly in the current directory, or in a subdirectory.
    # This is a common pattern, adjust if your DMG is different.
    extracted_app_path=$(find . -maxdepth 2 -name "${appPathInDmg}" -type d -print -quit)

    if [ -z "$extracted_app_path" ]; then
      echo "Error: Could not find ${appPathInDmg} after extracting DMG."
      ls -R . # List contents for debugging
      exit 1
    fi

    echo "Found app at $extracted_app_path"
    cp -R "$extracted_app_path" "$out/Applications/${appName}.app"

    # --- UNCOMMENT BELOW, if top fails ---
    # Option 2: Using hdiutil (more manual)
    # This might be necessary if undmg doesn't work for a particular DMG.
    # Make sure hdiutil is available in the build environment.
    # echo "Attaching DMG with hdiutil..."
    # mkdir ./dmg_mount
    # hdiutil attach "$src" -mountpoint ./dmg_mount -nobrowse -readonly

    # echo "Copying .app bundle..."
    # # The path inside the mounted DMG might vary. Common paths:
    # # ./dmg_mount/${appName}.app
    # # ./dmg_mount/Applications/${appName}.app
    # app_on_mount_path="./dmg_mount/${appPathInDmg}"

    # if [ ! -d "$app_on_mount_path" ]; then
    #   echo "Error: Could not find ${appPathInDmg} in mounted DMG."
    #   ls -R ./dmg_mount # List contents for debugging
    #   hdiutil detach ./dmg_mount
    #   exit 1
    # fi
    # cp -R "$app_on_mount_path" "$out/Applications/${appName}.app"

    # echo "Detaching DMG..."
    # hdiutil detach ./dmg_mount || true # Allow to fail if already detached

    # Optional: Clear macOS quarantine attribute if it causes issues
    # This is often needed for apps downloaded from the internet.
    # xattr -cr "$out/Applications/${appName}.app"

    runHook postInstall
  '';

  # Metadata about the package
  meta = with pkgs.lib; {
    description = "Custom build for ${appName}";
    # homepage = "https://example.com/your-app-homepage"; # Replace with actual homepage
    license = licenses.unfree; # Or whatever the actual license is
    platforms = platforms.darwin;
    # maintainers = [ maintainers.yourGithubUsername ]; # Optional: your username
  };
}
