{ config, pkgs, lib, inputs, dotfiles, ... }:
{
  services.flatpak = {
    enable = true;
    uninstallUnmanaged = false;
    
    update = {
      auto.enable = false;
    };
    
    packages = [
      # GUI to manage flatpak apps and permissions
      "com.github.tchx84.Flatseal"
    ];
  };
}
