_: {
  flake.modules.homeManager.applications =
    { config, pkgs, ... }:
    let
      url2app = pkgs.writeShellApplication {
        name = "url2app";
        runtimeInputs = with pkgs; [
          flatpak
          media-downloader
          mpv
          xdg-utils
          zenity
        ];
        text = ''
          url="''${1#x-url2app://}"
          url="''${url%%###mediaType=*}"

          case "$url" in
            http://* | https://*) ;;
            *) exit 1 ;;
          esac

          application="$(zenity --list --title="Open link with" --column="Application" "Default Browser (Zen)" "Floorp" "Media Downloader" "MPV")" || exit 0

          case "$application" in
            "Default Browser (Zen)") exec xdg-open "$url" ;;
            Floorp) exec flatpak run one.ablaze.floorp "$url" ;;
            "Media Downloader") exec media-downloader "$url" ;;
            MPV) exec mpv "$url" ;;
          esac
        '';
      };
    in
    {
      # Browser extension: https://addons.mozilla.org/firefox/addon/url2app/
      xdg.dataFile."applications/url2app.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=URL2App
        Exec=${url2app}/bin/url2app %u
        StartupNotify=false
        MimeType=x-scheme-handler/x-url2app;
        Terminal=false
      '';

      xdg.mimeApps.defaultApplications."x-scheme-handler/x-url2app" = [ "url2app.desktop" ];

      home.activation.url2appDesktopDatabase = config.lib.dag.entryAfter [ "writeBoundary" ] ''
        ${pkgs.desktop-file-utils}/bin/update-desktop-database "${config.xdg.dataHome}/applications"
      '';
    };
}
