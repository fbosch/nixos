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
      "be.alexandervanhee.gradia"
      "page.tesk.Refine"
      "com.mattjakeman.ExtensionManager"
      "com.plexamp.Plexamp"
      "app.zen_browser.zen"
      "org.qutebrowser.qutebrowser"
      "dev.zed.Zed"
    ];
  };
}
