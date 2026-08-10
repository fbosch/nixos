{ config, inputs, ... }:
let
  inherit (config.flake.lib) lazyDesktopApp;
in
{
  flake.modules.nixos.desktop = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      xrdb
      xhost
      xrandr
      xprop
      xwininfo
      xwayland
      xwayland-satellite
      setxkbmap
      wev
      (lazyDesktopApp pkgs {
        pkg = nwg-look;
        desktopItem = {
          name = "nwg-look";
          exec = "nwg-look";
          desktopName = "GTK Settings";
          genericName = "Adjust Look and Feel";
          comment = "Customizes GTK3 look and feel settings";
          icon = ./nwg-look.svg;
          terminal = false;
          notShowIn = [
            "GNOME"
            "KDE"
            "XFCE"
            "MATE"
          ];
          startupNotify = true;
          categories = [
            "GTK"
            "Settings"
            "DesktopSettings"
          ];
          keywords = [
            "windows"
            "preferences"
            "settings"
            "theme"
            "style"
            "appearance"
            "look"
          ];
        };
      })
      (lazyDesktopApp pkgs {
        pkg = nwg-displays;
        desktopItem = {
          name = "nwg-displays";
          exec = "nwg-displays";
          desktopName = "Displays Settings";
          genericName = "Output configuration utility";
          comment = "nwg-shell tool to configure outputs";
          icon = ./nwg-displays.svg;
          terminal = false;
          categories = [
            "Settings"
            "DesktopSettings"
          ];
        };
      })
      wlr-randr
      wl-clipboard
      xclip
      xsel
      autocutsel
      cliphist
      wl-clip-persist
      wtype
      xdotool
      swaynotificationcenter
      libnotify
      swayosd
      gsettings-desktop-schemas
      awww
    ];
  };
}
