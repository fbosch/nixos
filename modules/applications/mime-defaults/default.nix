let
  rpgMakerImageViewerScript = ./scripts/rpg-maker-image-viewer.sh;
  mkRpgMakerImageViewer =
    pkgs: rpgmasd:
    pkgs.writeShellApplication {
      name = "rpg-maker-image-viewer";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.loupe
        rpgmasd
        pkgs.util-linux
        pkgs.zenity
      ];
      text = ''
        export RPG_MAKER_DECODER_IDENTITY="${rpgmasd.name}"
        ${builtins.readFile rpgMakerImageViewerScript}
      '';
    };
in
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
      rpgMakerImageViewer = mkRpgMakerImageViewer pkgs pkgs.local.rpgmasd;
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

  perSystem =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      checks = lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
        rpgMakerImageViewerBuild = mkRpgMakerImageViewer pkgs config.packages.rpgmasd;
        rpgMakerImageViewer =
          pkgs.runCommand "rpg-maker-image-viewer-tests"
            {
              nativeBuildInputs = with pkgs; [
                bash
                coreutils
                findutils
                gnugrep
                util-linux
              ];
            }
            ''
              export PATH="${pkgs.bash}/bin:${pkgs.coreutils}/bin:${pkgs.findutils}/bin:${pkgs.gnugrep}/bin:${pkgs.util-linux}/bin:$PATH"
              export RPG_MAKER_VIEWER_SCRIPT=${rpgMakerImageViewerScript}
              ${pkgs.bash}/bin/bash ${./tests/rpg-maker-image-viewer.sh}
              touch "$out"
            '';
      };
    };
}
