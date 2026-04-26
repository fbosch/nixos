{
  flake.modules.homeManager.applications =
    { config
    , pkgs
    , ...
    }:
    {
      home.activation.zenProfileSetup = config.lib.dag.entryAfter [ "writeBoundary" ] ''
        ZEN_PROFILE="$HOME/.var/app/app.zen_browser.zen/.zen"
        if [ -d "$ZEN_PROFILE" ]; then
          ${pkgs.findutils}/bin/find "$ZEN_PROFILE" -maxdepth 1 -iname "*default*" -type d ! -name "static-*" | while IFS= read -r PROFILE_DIR; do
            ${pkgs.coreutils}/bin/install -m 0644 ${./user.js} "$PROFILE_DIR/user.js"
            echo "Zen user.js installed at $PROFILE_DIR/user.js"

            CACHE_DIR="$PROFILE_DIR/cache2"
            RAM_CACHE="/run/user/$(${pkgs.coreutils}/bin/id -u)/zen-cache"

            ${pkgs.coreutils}/bin/mkdir -p "$RAM_CACHE"

            if [ -d "$CACHE_DIR" ] && [ ! -L "$CACHE_DIR" ]; then
              ${pkgs.coreutils}/bin/rm -rf "$CACHE_DIR"
            fi

            if [ ! -L "$CACHE_DIR" ]; then
              ${pkgs.coreutils}/bin/ln -sf "$RAM_CACHE" "$CACHE_DIR"
              echo "Zen browser cache symlinked to RAM at $RAM_CACHE"
            fi
          done
        fi
      '';

      services.flatpak.packages = [
        "app.zen_browser.zen"
      ];

      services.flatpak.overrides."app.zen_browser.zen" = {
        Context = {
          sockets = [
            "wayland"
            "fallback-x11"
            "pulseaudio"
            "cups"
          ];
          shared = [
            "network"
            "ipc"
          ];
          devices = [ "dri" ];
          filesystems = [
            "/etc/localtime:ro"
            "/etc/zoneinfo:ro"
          ];
        };
        Environment = {
          MOZ_ENABLE_WAYLAND = "1";
          MOZ_USE_XINPUT2 = "1";
          GDK_BACKEND = "wayland";
          TZ = "Europe/Copenhagen";
        };
      };

      xdg.desktopEntries."app.zen_browser.zen" = {
        name = "Zen Browser";
        exec = "mullvad-exclude flatpak run --env=MOZ_ENABLE_WAYLAND=1 app.zen_browser.zen %U";
        icon = "app.zen_browser.zen";
        type = "Application";
        categories = [
          "Network"
          "WebBrowser"
        ];
        mimeType = [
          "text/html"
          "text/xml"
          "application/xhtml+xml"
          "x-scheme-handler/http"
          "x-scheme-handler/https"
          "application/x-xpinstall"
          "application/pdf"
          "application/json"
        ];
        startupNotify = false;
        terminal = false;
        settings = {
          StartupWMClass = "zen";
          X-MultipleArgs = "false";
          Keywords = "Internet;WWW;Browser;Web;Explorer;";
          X-Flatpak = "app.zen_browser.zen";
          PrefersNonDefaultGPU = "true";
        };
      };
    };
}
