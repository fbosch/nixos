{
  flake.modules.nixos.applications =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        selectdefaultapplication
        nemo-with-extensions

        # Archive format support
        zip
        p7zip # 7z, tar, and more formats
        unrar # RAR archive support

        # Image format libraries for thumbnails
        libwebp
        libjpeg
        libavif # AVIF image format
        libheif # HEIC/HEIF image format

        # Thumbnail generation
        gnome-desktop # Required for Nemo thumbnail generation
        gdk-pixbuf # Image loading library for thumbnails
        ffmpegthumbnailer # Video thumbnail support
        poppler-utils # PDF thumbnail support
      ];

      # Register heif-thumbnailer for HEIC/HEIF previews in Nemo.
      # libheif ships heif-thumbnailer but no gdk-pixbuf loader, so the
      # generic gdk-pixbuf-thumbnailer.thumbnailer does not cover these types.
      environment.etc."share/thumbnailers/heif.thumbnailer".text = ''
        [Thumbnailer Entry]
        TryExec=${pkgs.libheif}/bin/heif-thumbnailer
        Exec=${pkgs.libheif}/bin/heif-thumbnailer -s %s %i %o
        MimeType=image/heic;image/heif;image/heic-sequence;image/heif-sequence;
      '';
    };

  flake.modules.homeManager.applications =
    { pkgs
    , config
    , lib
    , ...
    }:
    let
      defaultFileExplorer = "nemo.desktop";
      defaultImageViewer = "loupe.desktop";
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

      home.sessionVariables = {
        XDG_DATA_DIRS = "$XDG_DATA_DIRS:${config.home.homeDirectory}/Desktop";
      };

      xdg = {
        mimeApps.defaultApplications = {
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
          "image/avif" = [ defaultImageViewer ]; # AVIF support
          "image/heic" = [ defaultImageViewer ]; # HEIC support
          "image/heif" = [ defaultImageViewer ]; # HEIF support

          # Archive formats
          "application/zip" = [ "org.gnome.FileRoller.desktop" ];
          "application/x-7z-compressed" = [ "org.gnome.FileRoller.desktop" ];
          "application/x-rar" = [ "org.gnome.FileRoller.desktop" ];
          "application/x-tar" = [ "org.gnome.FileRoller.desktop" ];
          "application/gzip" = [ "org.gnome.FileRoller.desktop" ];
        };

        # Make Nemo window transparent so Hyprland can apply blur
        # Create a separate CSS file that can be imported alongside existing GTK styles
        configFile = {
          "gtk-3.0/nemo-transparency.css".text = ''
            /* Nemo transparency for compositor blur */
            .nemo-window,
            .nemo-window .background {
              background-color: rgba(37, 37, 37, 0.75);
            }

            .nemo-window .view,
            .nemo-window treeview,
            .nemo-window scrolledwindow {
              background-color: rgba(37, 37, 37, 0.75);
            }

            .nemo-window .sidebar {
              background-color: rgba(37, 37, 37, 0.75);
            }

            /* Windows 11-style blue selection color */
            .nemo-window .view:selected,
            .nemo-window iconview:selected,
            .nemo-window .view:selected:focus,
            .nemo-window iconview:selected:focus {
              background-color: rgba(0, 120, 212, 0.8);
              color: #ffffff;
            }

            /* Windows 11-style blue drag selection area (rubberband) */
            .nemo-window .view.rubberband,
            .nemo-window iconview.rubberband,
            .nemo-window rubberband {
              background-color: rgba(0, 120, 212, 0.3);
              border: 1px solid rgba(0, 120, 212, 0.8);
            }

            /* Address bar — less transparent than window body */
            .nemo-window .primary-toolbar entry,
            .nemo-window toolbar entry {
              background-color: rgba(37, 37, 37, 0.90);
              -gtk-secondary-caret-color: transparent;
            }
          '';

          # Append import to existing gtk.css (creates if doesn't exist)
          "gtk-3.0/gtk.css".text = lib.mkAfter ''
            @import 'nemo-transparency.css';
          '';
        };
      };

      # Persist Nemo favorite directories (bookmarks) across rebuilds
      dconf.settings = {
        "org/nemo/sidebar-panels/tree" = {
          sync-bookmarks = true;
        };
        "org/cinnamon/desktop/applications/terminal" = {
          exec = "wezterm";
        };
        "org/nemo/preferences" = {
          enable-delete = true;
          show-delete-permanently = true;
          show-location-entry = true;
          mouse-use-extra-buttons = false;

          # Thumbnail settings
          show-image-thumbnails = "always"; # Enable image thumbnails
          thumbnail-limit = 10485760; # 10MB limit for thumbnailing (in bytes)

          # View preferences
          default-folder-viewer = "list-view"; # or "icon-view"
          show-hidden-files = true;

          # Performance
          show-full-path-titles = true;
          quick-renames-with-pause-in-between = true;
        };
        "org/nemo/window-state" = {
          start-with-sidebar = true;
        };
      };
    };
}
