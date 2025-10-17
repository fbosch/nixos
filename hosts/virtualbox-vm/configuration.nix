{ lib, config, inputs, pkgs, options, ... }:
{
  imports = [
    ../../modules/common.nix
    ../../modules/fonts.nix
    ../../modules/hyprland.nix
  ];

  system.stateVersion = "25.05";
  hardware.bluetooth.enable = false;

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.useOSProber = true;
  boot.loader.grub.configurationLimit = 42;

  networking.hostName = "rvn-vm";
  networking.networkmanager.enable = true;
  networking.timeServers = options.networking.timeServers.default ++ [ "time.nist.gov" ];

  services.upower.enable = true;
  services.dbus.enable = true;
  services.timesyncd.enable = true;

  security.rtkit.enable = true;
  security.polkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  services.gnome.gnome-keyring.enable = true;
  services.preload.enable = true;
  services.ananicy = {
    enable = true;
    package = pkgs.ananicy-cpp;
    rulesProvider = pkgs.ananicy-rules-cachyos;
  };

  zramSwap.enable = true;
  
  environment.systemPackages = with pkgs; [
    foot
    xdg-utils
  ];

}
