{
  flake.modules.homeManager.windows = { pkgs, lib, ... }:
    let
      # Define Windows installers to fetch and deploy
      windowsInstallers = [{
        name = "MEGAsyncSetup64.exe";
        url = "https://mega.nz/MEGAsyncSetup64.exe";
        sha256 =
          "6ffa84575a19e64a21e26f6a752854212b5c73555db1e20cee78ee44efe7781d";
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
      installerFiles = lib.listToAttrs (map
        (installer: {
          name = ".local/share/windows-installers/${installer.name}";
          value = { inherit (installer) source; };
        })
        fetchedInstallers);
    in
    {
      home.packages = with pkgs;
        [
          wine # Base Wine support
        ];

      # Place all Windows installers in a known location
      home.file = installerFiles;
    };
}
