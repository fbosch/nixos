{
  flake.modules.nixos.applications =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        selectdefaultapplication
      ];
    };

  flake.modules.homeManager.applications =
    { pkgs
    , lib
    , ...
    }:
    let
      defaultFileExplorer = "nemo.desktop";
      defaultImageViewer = "org.gnome.Loupe.desktop";
    in
    {
      home.packages = with pkgs; [
        xdg-utils
      ];

      # Flatpak file management applications
      services.flatpak.packages = [
        "org.gnome.FileRoller" # Archive manager
        "org.gnome.baobab" # Disk usage analyzer
        "org.gnome.TextEditor" # Text editor
      ];

      xdg.mimeApps = {
        # Explicitly add Loupe to associations so it wins over flatpak
        # mimeinfo.cache entries (e.g. Gradia) which appear earlier in
        # XDG_DATA_DIRS than the nix per-user profile.
        associations.added = {
          "image/png" = [ defaultImageViewer ];
          "image/jpeg" = [ defaultImageViewer ];
          "image/webp" = [ defaultImageViewer ];
        };
        defaultApplications = {
          "inode/directory" = [ defaultFileExplorer ];
          "application/x-gnome-saved-search" = [ defaultFileExplorer ];
          "application/x-directory" = [ defaultFileExplorer ];

          # Image formats
          "image/png" = [ defaultImageViewer ];
          "image/jpeg" = [ defaultImageViewer ];
          "image/jpg" = [ defaultImageViewer ];
          "image/gif" = [ defaultImageViewer ];
          "image/webp" = [ defaultImageViewer ];
          "image/svg+xml" = [ defaultImageViewer ];
          "image/bmp" = [ defaultImageViewer ];
          "image/tiff" = [ defaultImageViewer ];
          "image/x-icon" = [ defaultImageViewer ];
          "image/avif" = [ defaultImageViewer ];
          "image/heic" = [ defaultImageViewer ];
          "image/heif" = [ defaultImageViewer ];

          # Archive formats
          "application/zip" = [ "org.gnome.FileRoller.desktop" ];
          "application/x-7z-compressed" = [ "org.gnome.FileRoller.desktop" ];
          "application/x-rar" = [ "org.gnome.FileRoller.desktop" ];
          "application/x-tar" = [ "org.gnome.FileRoller.desktop" ];
          "application/gzip" = [ "org.gnome.FileRoller.desktop" ];
        };
      };
    };
}
