{
  flake.modules.nixos.applications = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      selectdefaultapplication
      nemo-with-extensions
      sushi
    ];

    xdg.mime.defaultApplications = {
      "inode/directory" = "nemo.desktop";
      "application/x-directory" = "nemo.desktop";
    };
  };

  flake.modules.homeManager.applications = { pkgs, config, lib, ... }:
    let
      defaultFileExplorer = "nemo.desktop";
      defaultImageViewer = "loupe.desktop";
    in
    {
      home.packages = with pkgs; [ loupe xdg-utils ];

      home.sessionVariables = {
        XDG_DATA_DIRS = "$XDG_DATA_DIRS:${config.home.homeDirectory}/Desktop";
      };

      xdg.mimeApps.defaultApplications = {
        "inode/directory" = [ defaultFileExplorer ];
        "application/x-directory" = [ defaultFileExplorer ];
        "image/png" = [ defaultImageViewer ];
        "image/jpeg" = [ defaultImageViewer ];
        "image/jpg" = [ defaultImageViewer ];
        "image/gif" = [ defaultImageViewer ];
        "image/webp" = [ defaultImageViewer ];
        "image/svg+xml" = [ defaultImageViewer ];
        "image/bmp" = [ defaultImageViewer ];
        "image/tiff" = [ defaultImageViewer ];
        "image/x-icon" = [ defaultImageViewer ];
      };

      # Persist Nemo favorite directories (bookmarks) across rebuilds
      dconf.settings = {
        "org/nemo/sidebar-panels/tree" = {
          # Sync bookmarks to avoid losing favorites
          # This ensures your custom bookmarks persist across NixOS rebuilds
          sync-bookmarks = true;
        };
      };
    };
}
