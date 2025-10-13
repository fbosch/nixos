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

    overrides = {
      global = {
        # Force Wayland for all flatpak apps (you're using Hyprland)
        Context.sockets = ["wayland" "!x11" "!fallback-x11"];
        
        Environment = {
          # Fix cursor theme
          XCURSOR_PATH = "/run/host/user-share/icons:/run/host/share/icons";
        };
      };
    };
  };
}
