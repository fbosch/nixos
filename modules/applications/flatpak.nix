{
  flake.modules.nixos.applications = _: { services.flatpak.enable = true; };
  flake.modules.homeManager.applications =
    { pkgs, config, ... }:
    {
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

      services.flatpak = {
        enable = true;
        uninstallUnmanaged = true;
        update = {
          onActivation = true;
          auto = {
            enable = true;
            onCalendar = "weekly";
          };
        };
        remotes = [
          {
            name = "flathub";
            location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
          }
        ];
        packages = [
          "com.github.tchx84.Flatseal"
          "io.github.flattool.Warehouse"
          "com.discordapp.Discord"
          "org.signal.Signal"
          "org.keepassxc.KeePassXC"
          "md.obsidian.Obsidian"
          "com.usebottles.bottles"
          "org.gnome.baobab"
          "org.gnome.FileRoller"
          "org.gnome.TextEditor"
          "org.gnome.World.PikaBackup"
          "app.zen_browser.zen"
          "be.alexandervanhee.gradia"
          "one.ablaze.floorp"
          "org.freedesktop.Platform.VulkanLayer.vkBasalt//25.08"
          "net.lutris.Lutris"
          "net.davidotek.pupgui2"
          "io.github.Faugus.faugus-launcher"
          # "org.freedesktop.Platform.VulkanLayer.MangoHud"
          # "net.displaycal.DisplayCAL"
          # "re.sonny.OhMySVG"
          # "dev.zed.Zed"
          # "com.rustdesk.RustDesk"
          # "org.localsend.localsend_app"
          # "com.todoist.Todoist"
          # "io.mgba.mGBA"
        ];

        overrides = {
          global = {
            Context.sockets = [
              "wayland"
              "!x11"
              "!fallback-x11"
            ];
            Context.filesystems = [
              "xdg-config/fontconfig:ro"
              "~/.local/share/fonts:ro"
              "/nix/store:ro"
            ];
          };

          "com.discordapp.Discord" = {
            Context = {
              sockets = [
                "wayland"
                "x11"
                "pulseaudio"
              ];
              shared = [
                "network"
                "ipc"
              ];
              devices = [ "all" ];
              filesystems = [
                "xdg-downloads"
                "xdg-videos"
                "xdg-pictures"
              ];
            };
            Environment = {
              # Enable Wayland support
              NIXOS_OZONE_WL = "1";
            };
          };

          "net.lutris.Lutris" = {
            Context = {
              sockets = [
                "x11"
                "wayland"
                "fallback-x11"
                "pulseaudio"
              ];
              shared = [
                "network"
                "ipc"
              ];
              devices = [ "all" ];
              filesystems = [
                "xdg-data/lutris:rw"
                "~/Games:rw"
                "~/.cache/lutris:ro"
              ];
            };
            Session.Talk = [ "org.freedesktop.Notifications" ];
          };

          "app.zen_browser.zen" = {
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
            };
            Environment = {
              MOZ_ENABLE_WAYLAND = "1";
              MOZ_USE_XINPUT2 = "1";
              GDK_BACKEND = "wayland";
            };
          };
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
