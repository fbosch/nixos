{}:
{
  services.flatpak = {
    enable = true;
    uninstallUnmanaged = true;

    update = {
      auto.enable = true;
      onActivation = true;
    };

    remotes = [
      {
        name = "flathub";
        location = "https://dl.flathub.com/repo/flathub.flatpakrepo";
      }
    ];

    packages = [
      "com.github.tchx84.Flatseal"
      "io.github.flattool.Warehouse"
      "com.discordapp.Discord"
      "org.signal.Signal"
      "org.keepassxc.KeePassXC"
      "md.obsidian.Obsidian"
      "me.proton.Mail"
      #"com.protonvpn.www"
      "com.bitwarden.desktop"
      "org.gnome.baobab"
      "org.gnome.font-viewer"
      # "org.qutebrowser.qutebrowser"
      # "com.google.Chrome"
      # "one.ablaze.floorp"
      # "com.visualstudio.code"
      # "org.videolan.VLC"
      # "net.lutris.Lutris"
      # "tv.plex.Desktop"
      # "io.github.wiiznokes.fan-control"
      # "com.vysp3r.ProtonPlus"
    ];
  };
}
