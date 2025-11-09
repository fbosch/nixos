{
  flake.modules.nixos.applications = { pkgs, ... }: {
    services.flatpak.enable = true;
  };
  flake.modules.homeManager.applications = {
    services.flatpak = {
      enable = true;
      uninstallUnmanaged = true;

      overrides = {
        global = {
          Context.sockets = [ "wayland" "!x11" "!fallback-x11" ];
          Context.filesystems = [
            "xdg-config/fontconfig:ro"
            "~/.local/share/fonts:ro"
            "/nix/store:ro"
          ];
        };
      };

      update = {
        onActivation = true;
        auto = {
          enable = true;
          onCalendar = "weekly";
        };
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
        "com.usebottles.bottles"
        "org.gnome.baobab"
        "org.gnome.FileRoller"
        "be.alexandervanhee.gradia"
        "com.plexamp.Plexamp"
        "app.zen_browser.zen"
        "dev.zed.Zed"
        "com.rustdesk.RustDesk"
        "org.localsend.localsend_app"
        "org.videolan.VLC"
        "io.github.wiiznokes.fan-control"
      ];
    };
  };
}
