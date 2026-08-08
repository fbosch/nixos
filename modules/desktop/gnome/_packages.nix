{ lazyDesktopApp }:
pkgs:
let
  lazyGucharmap = lazyDesktopApp pkgs {
    pkg = pkgs.gucharmap;
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
  };

  lazyGnomeTweaks = lazyDesktopApp pkgs {
    pkg = pkgs.gnome-tweaks;
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
  };
in
with pkgs;
[
  gtk4
  gtk4-layer-shell
  gnome-keyring
  lazyGnomeTweaks
  gnome-themes-extra
  gnome-calculator
  gnome-calendar
  gnomeExtensions.appindicator
  gnomeExtensions.blur-my-shell
  gnomeExtensions.mock-tray
  lazyGucharmap
  networkmanagerapplet
]
