{
  flake.modules.nixos.applications =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = with pkgs; [
        (nemo-with-extensions.override {
          extensions = [ local.nemo-image-converter ];
        })

        # Archive tools (used by the extract-to-folder action)
        zip
        p7zip
        unrar

        # Image format libraries for thumbnails
        libwebp
        libjpeg
        libavif # AVIF image format
        libheif # HEIC/HEIF image format
        webp-pixbuf-loader # WebP gdk-pixbuf loader + thumbnailer

        # Thumbnail generation
        gnome-desktop # Required for Nemo thumbnail generation
        gdk-pixbuf # Image loading library for thumbnails
        ffmpegthumbnailer # Video thumbnail support
        poppler-utils # PDF thumbnail support

        # Register heif-thumbnailer for HEIC/HEIF previews in Nemo.
        # libheif ships heif-thumbnailer but no gdk-pixbuf loader, so the
        # generic gdk-pixbuf-thumbnailer.thumbnailer does not cover these types.
        # Must be in systemPackages so the file lands under
        # /run/current-system/sw/share/thumbnailers/ (on XDG_DATA_DIRS);
        # environment.etc puts it in /etc/share/ which is not searched.
        (writeTextFile {
          name = "heif-thumbnailer-entry";
          destination = "/share/thumbnailers/heif.thumbnailer";
          text = ''
            [Thumbnailer Entry]
            TryExec=${libheif}/bin/heif-thumbnailer
            Exec=${libheif}/bin/heif-thumbnailer -s %s %i %o
            MimeType=image/heic;image/heif;image/heic-sequence;image/heif-sequence;
          '';
        })
      ];

      # Force Nemo's thumbnail size limit to 10 MB via a system-level dconf
      # override. Nemo's GSettings schema lives in a versioned subdirectory not
      # merged into the system profile, so the user dconf value is ignored and
      # Nemo falls back to its compiled-in 1 MB default. A system profile
      # override bypasses schema lookup and is always read.
      programs.dconf.profiles.user.databases = [
        {
          settings."org/nemo/preferences".thumbnail-limit = lib.gvariant.mkUint64 10485760;
        }
      ];
    };

  flake.modules.homeManager.applications =
    { pkgs
    , config
    , lib
    , ...
    }:
    {
      home.sessionVariables = {
        # Nemo ships its GSettings schema under a versioned gsettings-schemas/
        # subdirectory that NixOS does not merge into the system profile.
        # Adding the store path to XDG_DATA_DIRS lets GLib find it so dconf
        # keys like thumbnail-limit are respected instead of using the 1 MB default.
        # Also includes ~/Desktop so files there appear in XDG data lookups.
        XDG_DATA_DIRS = "$XDG_DATA_DIRS:${config.home.homeDirectory}/Desktop:${pkgs.nemo-with-extensions}/share/gsettings-schemas";
      };

      xdg = {
        # Make Nemo window transparent so Hyprland can apply blur
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

        dataFile."nemo/actions/extract-to-folder.nemo_action".text =
          let
            extractScript = pkgs.writeShellScript "nemo-extract-to-folder" ''
              set -euo pipefail
              file="$1"
              name=$(basename "$file")
              # Strip compound extensions first, then single extension
              for ext in .tar.gz .tar.bz2 .tar.xz .tar.zst .tar.lz4; do
                name="''${name%$ext}"
                [[ "$name" != "$(basename "$file")" ]] && break
              done
              name="''${name%.*}"
              outdir="$(dirname "$file")/$name"
              ${pkgs.p7zip}/bin/7z x -y "$file" -o"$outdir"
            '';
          in
          ''
            [Nemo Action]
            Active=true
            Name=Extract Here (to folder)
            Comment=Extract archive into a folder named after the file
            Exec=${extractScript} %F
            Icon-Name=package-x-generic
            Selection=single
            Extensions=zip;7z;rar;tar;gz;bz2;xz;zst;cab;iso;tgz;tbz2;txz;
            Terminal=false
          '';
      };

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
          show-image-thumbnails = "always";
          # thumbnail-limit is set via programs.dconf.profiles.user in the
          # NixOS module — the schema isn't on the search path so the HM
          # dconf value is silently ignored by Nemo.

          # View preferences
          default-folder-viewer = "list-view";
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
