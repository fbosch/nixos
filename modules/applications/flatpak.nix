{
  flake.modules.nixos.applications = _: { services.flatpak.enable = true; };
  flake.modules.homeManager.applications =
    { pkgs, ... }:
    {
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
          "org.gnome.Decibels"
          "org.gnome.World.PikaBackup"
          "app.zen_browser.zen"
          "be.alexandervanhee.gradia"
          "com.plexamp.Plexamp"
          "one.ablaze.floorp"
          "io.github.wiiznokes.fan-control"
          "tv.plex.PlexDesktop"
          "com.obsproject.Studio"
          "com.obsproject.Studio.Plugin.OBSVkCapture"
          "org.freedesktop.Platform.VulkanLayer.vkBasalt//25.08"
          "org.freedesktop.Platform.VulkanLayer.MangoHud"
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
            Context.sockets = [
              "wayland"
              "x11"
              "pulseaudio"
            ];
            Context.shared = [
              "network"
              "ipc"
            ];
            Context.devices = [ "all" ];
            Context.filesystems = [
              "xdg-downloads"
              "xdg-videos"
              "xdg-pictures"
            ];
            Environment = {
              # Enable Wayland support
              NIXOS_OZONE_WL = "1";
            };
          };

          # Bottles - disabled in favor of native nixpkgs version
          # "com.usebottles.bottles" = {
          #   Context.sockets = [
          #     "wayland"
          #     "x11"
          #     "fallback-x11"
          #     "pulseaudio"
          #   ];
          #   Context.shared = [
          #     "network"
          #     "ipc"
          #   ];
          #   Context.devices = [
          #     "dri"
          #     "all"
          #   ];
          #   Context.filesystems = [
          #     "xdg-documents"
          #     "xdg-download"
          #     "xdg-music"
          #     "xdg-pictures"
          #     "xdg-videos"
          #     "home"
          #     "host"
          #     "/tmp/.X11-unix"
          #   ];
          #   Environment = {
          #     # Ensure DISPLAY is set correctly
          #     DISPLAY = ":0";
          #     # Disable Wayland for Wine compatibility
          #     GDK_BACKEND = "x11";
          #     # Wine needs these for proper X11 support
          #     XDG_SESSION_TYPE = "x11";
          #   };
          # };
        };
      };
    };
}
