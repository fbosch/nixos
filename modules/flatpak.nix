{ config, pkgs, lib, inputs, dotfiles, ... }:
{
  services.flatpak = {
    enable = true;
    uninstallUnmanaged = false;
    
    update = {
      auto.enable = false;
      onActivation = true;
    };

    
    packages = [
      # GUI to manage flatpak apps and permissions
      "com.github.tchx84.Flatseal"
      "com.disordapp.Discord"
      # "org.signal.Signal"
      # "org.keepassxc.KeePassXC"
      # "md.obsidian.Obsidian"
      # "me.proton.Mail"
      # "com.protonvpn.www"
    ];
  };
}
