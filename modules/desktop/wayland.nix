{ inputs, ... }:
{
  flake.modules.homeManager.desktop = { pkgs, ... }: {
    home.packages = with pkgs; [
      # waycorner
      nwg-look
      nwg-displays
      wl-clipboard
      wl-clipboard-x11
      cliphist
      waybar
      swaynotificationcenter
      swayimg
      libnotify
      rofi
    ];
  };
}
