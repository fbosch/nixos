{ inputs, ... }:
{
  flake.modules.nixos.desktop = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      xwayland
      # xorg.xrdb
      # xorg.xhost
      # xorg.xrandr
      # xorg.xprop
      # xorg.xwininfo
    ];
  };

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
