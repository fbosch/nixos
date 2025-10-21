{
  pkgs,
  inputs,
  options,
  system,
  ...
}:
let
  theme = inputs.distro-grub-themes.packages.${system}.asus-tuf-grub-theme;
in
{

  imports = [ ../../modules/system ];

  system.stateVersion = "25.05";
  hardware.bluetooth.enable = false;

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.useOSProber = true;
  boot.loader.grub.configurationLimit = 42;
  boot.loader.grub.theme = theme;
  boot.loader.grub.splashImage = "${theme}/splash_image.jpg";

  nixpkgs.overlays = [ inputs.mac-style-plymouth.overlays.default ];
  boot.plymouth = {
    enable = true;
    theme = "mac-style";
    themePackages = [ pkgs.mac-style-plymouth ];
  };

  networking = {
    hostName = "rvn-vm";
    networkmanager.enable = true;
    timeServers = options.networking.timeServers.default ++ [ "time.nist.gov" ];
  };

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
