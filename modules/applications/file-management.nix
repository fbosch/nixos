{
  flake.modules.nixos.applications =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        selectdefaultapplication
        nemo-with-extensions
        sushi
        zip
      ];

      xdg.mime.defaultApplications = {
        "inode/directory" = "nemo.desktop";
        "application/x-directory" = "nemo.desktop";
      };
    };

  flake.modules.homeManager.applications =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      defaultFileExplorer = "nemo.desktop";
      defaultImageViewer = "loupe.desktop";
    in
    {
      home.packages = with pkgs; [
        loupe
        xdg-utils
      ];

      home.sessionVariables = {
        XDG_DATA_DIRS = "$XDG_DATA_DIRS:${config.home.homeDirectory}/Desktop";
      };

      xdg = {
        mimeApps.defaultApplications = {
          "inode/directory" = [ defaultFileExplorer ];
          "application/x-gnome-saved-search" = [ defaultFileExplorer ];
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

            /* Fix text selection in address bar */
            .nemo-window .primary-toolbar entry,
            .nemo-window toolbar entry {
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
        };
        "org/nemo/window-state" = {
          start-with-sidebar = true;
        };
      };
    };
}
