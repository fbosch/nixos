{ config, pkgs, lib, inputs, dotfiles, ... }:
{
  services.flatpak = {
    enable = true;
    uninstallUnmanaged = false;
    
    update = {
      auto.enable = false;
      # onActivation = true;
    };

    remotes = [{
      name = "flathub";
      location = "https://dl.flathub.com/repo/flathub.flatpakrepo";
    }];
    
    packages = [
      "com.github.tchx84.Flatseal"
      "com.discordapp.Discord"
      "org.signal.Signal"
      "org.keepassxc.KeePassXC"
      "md.obsidian.Obsidian"
      "me.proton.Mail"
      "com.protonvpn.www"
      "com.bitwarden.desktop"
      "com.google.Chrome"
      "one.ablaze.floorp"
      "com.visualstudio.code"
      "org.videolan.VLC"
      "net.lutris.Lutris"
      "tv.plex.Desktop"
      "io.github.wiiznokes.fan-control"
      "org.gnome.Loupe"
      "io.github.flattool.Ignition"
   ];
  };
}
