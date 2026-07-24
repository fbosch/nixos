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
      defaultMediaPlayer = "mpv.desktop";
      defaultExeLauncher = "faugus-launcher.desktop";
      defaultWebBrowser = "app.zen_browser.zen.desktop";
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
        enable = true;

        # Explicitly add Loupe to associations so it wins over flatpak
        # mimeinfo.cache entries (e.g. Gradia) which appear earlier in
        # XDG_DATA_DIRS than the nix per-user profile.
        associations.added = {
          "image/png" = [ defaultImageViewer ];
          "image/jpeg" = [ defaultImageViewer ];
          "image/webp" = [ defaultImageViewer ];

          "video/3gpp" = [ defaultMediaPlayer ];
          "video/mp2t" = [ defaultMediaPlayer ];
          "video/mp4" = [ defaultMediaPlayer ];
          "video/mpeg" = [ defaultMediaPlayer ];
          "video/ogg" = [ defaultMediaPlayer ];
          "video/quicktime" = [ defaultMediaPlayer ];
          "video/webm" = [ defaultMediaPlayer ];
          "video/x-matroska" = [ defaultMediaPlayer ];
          "video/x-msvideo" = [ defaultMediaPlayer ];
          "video/x-ms-wmv" = [ defaultMediaPlayer ];

          # Common MIME types for Windows executables
          "application/x-ms-dos-executable" = [ defaultExeLauncher ];
          "application/x-dosexec" = [ defaultExeLauncher ];
          "application/x-msdownload" = [ defaultExeLauncher ];
          "application/vnd.microsoft.portable-executable" = [ defaultExeLauncher ];
        };
        defaultApplications = {
          # Browser defaults
          "text/html" = [ defaultWebBrowser ];
          "x-scheme-handler/http" = [ defaultWebBrowser ];
          "x-scheme-handler/https" = [ defaultWebBrowser ];
          "x-scheme-handler/about" = [ defaultWebBrowser ];
          "x-scheme-handler/unknown" = [ defaultWebBrowser ];

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

          # Video formats
          "video/3gpp" = [ defaultMediaPlayer ];
          "video/mp2t" = [ defaultMediaPlayer ];
          "video/mp4" = [ defaultMediaPlayer ];
          "video/mpeg" = [ defaultMediaPlayer ];
          "video/ogg" = [ defaultMediaPlayer ];
          "video/quicktime" = [ defaultMediaPlayer ];
          "video/webm" = [ defaultMediaPlayer ];
          "video/x-matroska" = [ defaultMediaPlayer ];
          "video/x-msvideo" = [ defaultMediaPlayer ];
          "video/x-ms-wmv" = [ defaultMediaPlayer ];

          # Windows executables
          "application/x-ms-dos-executable" = [ defaultExeLauncher ];
          "application/x-dosexec" = [ defaultExeLauncher ];
          "application/x-msdownload" = [ defaultExeLauncher ];
          "application/vnd.microsoft.portable-executable" = [ defaultExeLauncher ];

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
