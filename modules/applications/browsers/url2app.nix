_: {
  flake.modules.homeManager.applications =
    { pkgs, ... }:
    let
      url2app = pkgs.writeShellApplication {
        name = "url2app";
        runtimeInputs = with pkgs; [
          flatpak
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

          application="$(zenity --list --title="Open link with" --column="Application" "Default Browser (Zen)" "Floorp" "MPV")" || exit 0

          case "$application" in
            "Default Browser (Zen)") exec xdg-open "$url" ;;
            Floorp) exec flatpak run one.ablaze.floorp "$url" ;;
            MPV) exec mpv "$url" ;;
          esac
        '';
      };
    in
    {
      # Browser extension: https://addons.mozilla.org/firefox/addon/url2app/
      xdg.desktopEntries.url2app = {
        name = "URL2App";
        exec = "${url2app}/bin/url2app %u";
        mimeType = [ "x-scheme-handler/x-url2app" ];
        noDisplay = true;
        terminal = false;
      };

      xdg.mimeApps.defaultApplications."x-scheme-handler/x-url2app" = [ "url2app.desktop" ];
    };
}
