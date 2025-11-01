{
  flake.modules.nixos.flatpak = { pkgs, ... }: {
    services.flatpak.enable = true;
  };
  flake.modules.homeManager.flatpak = {
    services.flatpak = {
      enable = true;
      uninstallUnmanaged = true;

      update = {
        auto.enable = true;
        onActivation = true;
      };

      remotes = [{
        name = "flathub";
        location = "https://dl.flathub.com/repo/flathub.flatpakrepo";
      }];

      packages = [
        "com.github.tchx84.Flatseal"
        "io.github.flattool.Warehouse"
        "com.discordapp.Discord"
        "org.signal.Signal"
        "org.keepassxc.KeePassXC"
        "md.obsidian.Obsidian"
        "org.gnome.baobab"
        "be.alexandervanhee.gradia"
        "com.plexamp.Plexamp"
        "app.zen_browser.zen"
        "dev.zed.Zed"
        "nz.mega.MEGAsync"
      ];

      overrides = {
        global = {
          Context = {
            sockets = [
              "wayland"
              "fallback-x11"
            ];
            devices = [
              "dri"
            ];
          };
          Environment = {
            WAYLAND_DISPLAY = "wayland-1";
            XDG_SESSION_TYPE = "wayland";
          };
        };

        "nz.mega.MEGAsync" = {
          Context = {
            sockets = [
              "wayland"
              "fallback-x11"
              "x11"
            ];
            filesystems = [
              "xdg-run/X11"
              "/tmp/.X11-unix"
            ];
          };
          Environment = {
            QT_QPA_PLATFORM = "wayland;xcb";
            DISABLE_WAYLAND = "0";
          };
        };
      };
    };
  };
}
