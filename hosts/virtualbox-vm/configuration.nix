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

  boot = {
    loader.grub = {
      enable = true;
      device = "/dev/sda";
      useOSProber = true;
      configurationLimit = 42;
      theme = theme;
      splashImage = "${theme}/splash_image.jpg";
    };

    plymouth = {
      enable = true;
      theme = "mac-style";
      themePackages = [ pkgs.mac-style-plymouth ];
    };
  };

  nixpkgs.overlays = [ inputs.mac-style-plymouth.overlays.default ];

  networking = {
    hostName = "rvn-vm";
    networkmanager.enable = true;
    timeServers = options.networking.timeServers.default ++ [ "time.nist.gov" ];
  };

  zramSwap.enable = true;
  security.polkit.enable = true;

  services = {
    upower.enable = true;
    dbus.enable = true;
    timesyncd.enable = true;
    preload.enable = true;
    ananicy = {
      enable = true;
      package = pkgs.ananicy-cpp;
      rulesProvider = pkgs.ananicy-rules-cachyos;
    };
  };

  environment.systemPackages = with pkgs; [
    foot
    xdg-utils
  ];
}
