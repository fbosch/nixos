{
  flake.modules.nixos.flatpak = { pkgs, ... }: {
    services.flatpak.enable = true;
    
    xdg.portal = {
      enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
      config.common.default = "gtk";  # Use GTK portal by default
    };
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
      ];
    };
  };
}
