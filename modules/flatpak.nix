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
      
      # Or use this full-featured app store instead (works without GNOME)
      # "io.github.flattool.Warehouse"
      
      # Example apps:
      # "com.spotify.Client"
      # "com.discordapp.Discord"
    ];

    overrides = {
      global = {
        # Force Wayland for all flatpak apps (you're using Hyprland)
        Context.sockets = ["wayland" "!x11" "!fallback-x11"];
        
        Environment = {
          # Fix cursor theme
          XCURSOR_PATH = "/run/host/user-share/icons:/run/host/share/icons";
          # Dark theme
          GTK_THEME = "Adwaita:dark";
        };
      };
    };
  };
}
