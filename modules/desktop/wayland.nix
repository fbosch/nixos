{ inputs, ... }:

{
  flake.modules.homeManager.desktop = { pkgs, ... }: {
    home.packages = with pkgs; [
      hyprpaper
      hyprprop
      hyprpicker
      # waycorner
      wl-clipboard
      wl-clipboard-x11
      cliphist
      waybar
      swaynotificationcenter
      libnotify
      rofi
      inputs.hyprland-contrib.packages.${pkgs.system}.grimblast
    ];
  };
}
