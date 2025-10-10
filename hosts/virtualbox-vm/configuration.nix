{ config, pkgs, ... }:

{
  imports = [
    ../../modules/common.nix
  ];

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.useOSProber = true;

  networking.hostName = "rvn";
  networking.networkmanager.enable = true;

  services.upower.enable = true;

  virtualisation.virtualbox.guest.enable = true;
  virtualisation.virtualbox.guest.dragAndDrop = true;
  virtualisation.virtualbox.guest.clipboard = true;

  programs.hyprland = { 
    enable = true;
    xwayland.enable = true;
  };

  environment.systemPackages = with pkgs; [ 
    mako
    wezterm
    kitty
    foot
    waybar
    hyprpaper
  ];

  system.stateVersion = "25.05";
}
