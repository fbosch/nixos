{ inputs, ... }:

{
  flake.modules.homeManager."desktop/wayland" = { pkgs, ... }: {
    home.packages = with pkgs; [
      hyprpaper
      hyprprop
      hyprpicker
      waycorner
      wl-clipboard
      waybar
      swaynotificationcenter
      libnotify
      rofi
      inputs.hyprland-contrib.packages.${pkgs.system}.grimblast
    ];
  };
}
