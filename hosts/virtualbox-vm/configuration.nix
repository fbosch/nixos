{ pkgs, options, ... }:
{
  imports = [
    ../../modules/system
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

  zramSwap.enable = true;
  services.upower.enable = true;
  services.dbus.enable = true;
  services.timesyncd.enable = true;

  security.polkit.enable = true;

  services.preload.enable = true;
  services.ananicy = {
    enable = true;
    package = pkgs.ananicy-cpp;
    rulesProvider = pkgs.ananicy-rules-cachyos;
  };
  
  environment.systemPackages = with pkgs; [
    foot
    xdg-utils
  ];
}
