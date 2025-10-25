_: {
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
      "me.proton.Mail"
      "org.gnome.baobab"
      "io.github.efogdev.mpris-timer"
      "io.github.seadve.Kooha"
      "dev.geopjr.Calligraphy"
      "net.nokyan.Resources"
      "be.alexandervanhee.gradia"
      "page.tesk.Refine"
      "io.github.johnfactotum.Runemaster"
      "com.mattjakeman.ExtensionManager"
      "com.plexamp.Plexamp"
      "app.zen_browser.zen"
      "org.qutebrowser.qutebrowser"
      "dev.zed.Zed"
    ];
  };
}
