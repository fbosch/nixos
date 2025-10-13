{ config, pkgs, lib, inputs, dotfiles, ... }:

{
  services.flatpak.enable = true;
  services.flatpak.uninstallUnmanaged = false;
  services.flatpak.update.auto.enable = false;
  
  services.flatpak.packages = [
    
  ];
}
