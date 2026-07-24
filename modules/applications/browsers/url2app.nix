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
      nativeHost = pkgs.writeText "url2app-native-host" (builtins.readFile ./url2app-native-host.py);
      nativeHostManifest = pkgs.writeText "com.add0n.node.json" (
        builtins.toJSON {
          name = "com.add0n.node";
          description = "Restricted External Application Button host";
          path = "${config.home.homeDirectory}/.mozilla/native-messaging-hosts/com.add0n.node";
          type = "stdio";
          allowed_extensions = [ "{65b77238-bb05-470a-a445-ec0efe1d66c4}" ];
        }
      );
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

      services.flatpak.overrides = {
        "app.zen_browser.zen".Context.persistent = [ ".mozilla" ];
        "one.ablaze.floorp".Context.persistent = [ ".mozilla" ];
      };

      home.activation.url2appDesktopDatabase = config.lib.dag.entryAfter [ "writeBoundary" ] ''
        ${pkgs.desktop-file-utils}/bin/update-desktop-database "${config.xdg.dataHome}/applications"
      '';

      home.activation.url2appNativeMessaging = config.lib.dag.entryAfter [ "writeBoundary" ] ''
        for app_id in app.zen_browser.zen one.ablaze.floorp; do
          directory="$HOME/.var/app/$app_id/.mozilla/native-messaging-hosts"
          ${pkgs.coreutils}/bin/install -D -m 0755 ${nativeHost} "$directory/com.add0n.node"
          ${pkgs.coreutils}/bin/install -m 0644 ${nativeHostManifest} "$directory/com.add0n.node.json"
        done
      '';
    };
}
