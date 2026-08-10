{ config, ... }:
let
  inherit (config.flake.lib) lazyDesktopApp;
in
{
  flake.modules.nixos.desktop = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      json-glib
      gtk4
      gtk4-layer-shell
      gnome-keyring
      (lazyDesktopApp pkgs {
        pkg = gnome-tweaks;
        exe = "gnome-tweaks";
        desktopItem = {
          name = "org.gnome.tweaks";
          exec = "gnome-tweaks";
          desktopName = "Tweaks";
          comment = "Tweak advanced GNOME settings";
          icon = ./gnome-tweaks.svg;
          terminal = false;
          onlyShowIn = [
            "GNOME"
            "Unity"
            "Pantheon"
          ];
          startupNotify = true;
          startupWMClass = "gnome-tweaks";
          categories = [
            "GNOME"
            "GTK"
            "Utility"
          ];
          keywords = [
            "Settings"
            "Advanced"
            "Preferences"
            "Fonts"
            "Theme"
            "Keyboard"
          ];
        };
      })
      gnome-themes-extra
      gnome-calculator
      gnomeExtensions.appindicator
      gnomeExtensions.blur-my-shell
      gnomeExtensions.mock-tray
      (lazyDesktopApp pkgs {
        pkg = gucharmap;
        desktopItem = {
          name = "gucharmap";
          exec = "gucharmap";
          desktopName = "Character Map";
          comment = "Insert special characters into documents";
          icon = "accessories-character-map";
          terminal = false;
          startupNotify = true;
          categories = [
            "GNOME"
            "GTK"
            "Utility"
          ];
          keywords = [
            "font"
            "unicode"
          ];
        };
      })
      networkmanagerapplet
    ];
  };
}
