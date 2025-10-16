{ config, pkgs, options, ... }:

{
  imports = [
    ../../modules/common.nix
    ../../modules/fonts.nix
  ];

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

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
    ];
    config.common.default = "gtk";
  };

  zramSwap.enable = true;

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    GDK_BACKEND = "wayland,x11";
    QT_QPA_PLATFORM = "wayland;xcb";
    GSK_RENDERER = "cairo";
    WLR_NO_HARDWARE_CURSORS = "1";
    WLR_RENDERER_ALLOW_SOFTWARE = "1";
  };

  environment.systemPackages = with pkgs; [
    foot
    xdg-utils
  ];

  system.stateVersion = "25.05";
}
