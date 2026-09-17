{
  flake.modules.nixos.applications =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        selectdefaultapplication
      ];
    };

  flake.modules.homeManager.applications =
    { pkgs, ... }:
    let
      defaultFileExplorer = "nemo.desktop";
      defaultImageViewer = "org.gnome.Loupe.desktop";
      defaultMediaPlayer = "mpv.desktop";
      defaultBlpViewer = "xnviewmp.desktop";
      defaultExeLauncher = "faugus-launcher.desktop";
      defaultWebBrowser = "app.zen_browser.zen.desktop";
      defaultRpgMakerImageViewer = "rpg-maker-image-viewer.desktop";
      rpgMakerImageViewer = pkgs.writeShellApplication {
        name = "rpg-maker-image-viewer";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.loupe
          pkgs.local.rpgmasd
          pkgs.systemd
        ];
        text = ''
          if [[ $# -eq 0 ]]; then
            exit 1
          fi

          tmp_dir="$(mktemp -d --tmpdir="''${XDG_RUNTIME_DIR:?}" rpg-maker-loupe.XXXXXX)"
          keep_temp=false
          cleanup() {
            if [[ $keep_temp == false ]]; then
              rm -rf -- "$tmp_dir"
            fi
          }
          trap cleanup EXIT

          declare -A decrypted_dirs=()
          selected_outputs=()
          index=0
          for input in "$@"; do
            if [[ ! -f $input ]]; then
              printf 'File not found: %s\n' "$input" >&2
              exit 1
            fi

            source_dir="$(realpath -e -- "$(dirname -- "$input")")"
            if [[ -z ''${decrypted_dirs["$source_dir"]+x} ]]; then
              ((index += 1))
              item_dir="$tmp_dir/$index"
              mkdir -p -- "$item_dir"
              rpgmasd decrypt \
                --input-dir "$source_dir" \
                --output-dir "$item_dir" \
                >/dev/null
              decrypted_dirs["$source_dir"]="$item_dir"
            fi

            item_dir="''${decrypted_dirs["$source_dir"]}"
            selected_output="$item_dir/$(basename -- "''${input%.*}").png"
            if [[ ! -f $selected_output ]]; then
              printf 'Unable to decrypt: %s\n' "$input" >&2
              exit 1
            fi
            selected_outputs+=("$selected_output")
          done

          loupe "''${selected_outputs[@]}"
          systemd-run --user --quiet --collect \
            --unit="rpg-maker-loupe-cleanup-''${tmp_dir##*.}" \
            --on-active=10m \
            ${pkgs.coreutils}/bin/rm -rf -- "$tmp_dir"
          keep_temp=true
        '';
      };
    in
    {
      # Flatpak file management applications
      services.flatpak.packages = [
        "org.gnome.FileRoller" # Archive manager
        "org.gnome.baobab" # Disk usage analyzer
        "org.gnome.TextEditor" # Text editor
      ];

      xdg.mimeApps = {
        enable = true;

        # Explicitly add the configured image viewers to associations so they
        # win over flatpak mimeinfo.cache entries (e.g. Gradia) which appear
        # earlier in XDG_DATA_DIRS than the nix per-user profile.
        associations.added = {
          "image/png" = [ defaultImageViewer ];
          "image/jpeg" = [ defaultImageViewer ];
          "image/webp" = [ defaultImageViewer ];
          "image/x-blp" = [ defaultBlpViewer ];
          "image/x-rpg-maker-encrypted" = [ defaultRpgMakerImageViewer ];

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
          "image/x-blp" = [ defaultBlpViewer ];
          "image/x-rpg-maker-encrypted" = [ defaultRpgMakerImageViewer ];

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
      xdg.desktopEntries = {
        xnviewmp = {
          name = "XnView MP";
          comment = "Image viewer for Blizzard Picture textures";
          exec = "${pkgs.xnviewmp}/bin/xnviewmp %F";
          icon = "xnviewmp";
          categories = [ "Graphics" ];
          mimeType = [ "image/x-blp" ];
          terminal = false;
          type = "Application";
        };
        rpg-maker-image-viewer = {
          name = "RPG Maker Image Viewer";
          comment = "Decrypt and open RPG Maker images in Loupe";
          exec = "${rpgMakerImageViewer}/bin/rpg-maker-image-viewer %F";
          icon = "org.gnome.Loupe";
          categories = [ "Graphics" ];
          mimeType = [ "image/x-rpg-maker-encrypted" ];
          noDisplay = true;
          terminal = false;
          type = "Application";
        };
      };
    };
}
