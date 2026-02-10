{ inputs, ... }:
{
  flake.modules.nixos.windows =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        freerdp
        xdg-utils
      ];
    };

  flake.modules.homeManager.windows =
    { pkgs, lib, ... }:
    let
      # Define Windows installers to fetch and deploy
      windowsInstallers = [
        {
          name = "MEGAsyncSetup64.exe";
          url = "https://mega.nz/MEGAsyncSetup64.exe";
          sha256 = "92a7ca073bdb0eca85d2af66a20fd5970843c42eab535f953ce59e83f6aa31e0";
        }
        # Add more Windows installers here as needed
        # Example:
        # {
        #   name = "SomeApp.exe";
        #   url = "https://example.com/SomeApp.exe";
        #   sha256 = "...";
        # }
      ];

      # Fetch all installers
      fetchedInstallers = map
        (installer: {
          inherit (installer) name;
          source = pkgs.fetchurl { inherit (installer) url sha256; };
        })
        windowsInstallers;

      # Generate home.file entries for all installers
      installerFiles = lib.listToAttrs (
        map
          (installer: {
            name = ".local/share/windows-installers/${installer.name}";
            value = { inherit (installer) source; };
          })
          fetchedInstallers
      );
    in
    {
      home.packages = with pkgs; [
        winboat
        inputs.winapps.packages.${pkgs.stdenv.hostPlatform.system}.winapps
        inputs.winapps.packages.${pkgs.stdenv.hostPlatform.system}.winapps-launcher
        freerdp
      ];

      # Flatpak Windows compatibility applications
      # Note: Flatpak overrides are centralized in flatpak.nix
      services.flatpak.packages = [
        "com.usebottles.bottles" # Run Windows applications
      ];

      # XDG desktop integration
      xdg.mimeApps.enable = true;

      # Create winapps configuration directory and place all Windows installers in a known location
      home.file = lib.mkMerge [
        installerFiles
        {
          ".config/winapps/.keep".text = "";

          # WinApps configuration for USB passthrough
          ".config/winapps/winapps.conf".text = ''
            # USB devices to pass through to Windows VM
            # Format: RDP_USB0="0853:0317" for REALFORCE keyboard
            RDP_USB0="0853:0317"
          '';
        }
      ];

    };
}
