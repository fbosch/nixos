{
  flake.modules.homeManager.applications =
    { pkgs, config, ... }:
    {
      home.packages = with pkgs; [ local.helium-browser ];

      home.activation.zenCacheToRAM = config.lib.dag.entryAfter [ "writeBoundary" ] ''
        ZEN_PROFILE="$HOME/.var/app/app.zen_browser.zen/.zen"
        if [ -d "$ZEN_PROFILE" ]; then
          PROFILE_DIR=$(${pkgs.findutils}/bin/find "$ZEN_PROFILE" -maxdepth 1 -name "*.default*" -type d | ${pkgs.coreutils}/bin/head -1)
          if [ -n "$PROFILE_DIR" ] && [ -d "$PROFILE_DIR" ]; then
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
          fi
        fi
      '';

      services.flatpak.packages = [ "app.zen_browser.zen" ];

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
            "/etc/timezone:ro"
          ];
        };
        Environment = {
          MOZ_ENABLE_WAYLAND = "1";
          MOZ_USE_XINPUT2 = "1";
          GDK_BACKEND = "wayland";
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

      xdg.mimeApps.defaultApplications = {
        "text/html" = [ "io.github.zen_browser.zen.desktop" ];
        "x-scheme-handler/http" = [ "io.github.zen_browser.zen.desktop" ];
        "x-scheme-handler/https" = [ "io.github.zen_browser.zen.desktop" ];
        "x-scheme-handler/about" = [ "io.github.zen_browser.zen.desktop" ];
        "x-scheme-handler/unknown" = [ "io.github.zen_browser.zen.desktop" ];
      };
    };
}
