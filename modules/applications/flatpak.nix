{
  flake.modules.nixos.applications = _: { services.flatpak.enable = true; };
  flake.modules.homeManager.applications =
    _:
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
          # Flatpak management tools
          "com.github.tchx84.Flatseal" # Flatpak permission manager
          "io.github.flattool.Warehouse" # Flatpak app manager

          # Browsers
          "be.alexandervanhee.gradia"
          "one.ablaze.floorp"

          # Productivity
          "org.keepassxc.KeePassXC"
          "md.obsidian.Obsidian"

          # Moved to domain-specific modules:
          # - browsers.nix: app.zen_browser.zen
          # - communication.nix: com.discordapp.Discord, org.signal.Signal
          # - file-management.nix: org.gnome.FileRoller, org.gnome.baobab, org.gnome.TextEditor
          # - media.nix: org.gnome.Decibels, com.plexamp.Plexamp, tv.plex.PlexDesktop, com.obsproject.Studio
          # - gaming.nix: net.lutris.Lutris, net.davidotek.pupgui2, io.github.Faugus.faugus-launcher, org.freedesktop.Platform.VulkanLayer.vkBasalt
          # - windows.nix: com.usebottles.bottles
          # - system.nix: org.gnome.World.PikaBackup

          # Commented out / Future additions:
          # "org.freedesktop.Platform.VulkanLayer.MangoHud"
          # "net.displaycal.DisplayCAL"
          # "re.sonny.OhMySVG"
          # "dev.zed.Zed"
          # "com.rustdesk.RustDesk" (would go in communication.nix)
          # "org.localsend.localsend_app" (would go in communication.nix)
          # "com.todoist.Todoist" (would go in productivity.nix)
          # "io.mgba.mGBA" (would go in gaming.nix)
        ];

        # Flatpak application overrides
        # Note: All overrides are centralized here even if packages are defined
        # in domain-specific modules (gaming.nix, media.nix, etc.) to avoid
        # potential merge conflicts with the services.flatpak.overrides option
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
        };
      };
    };
}
