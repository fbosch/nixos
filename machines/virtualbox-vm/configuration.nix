{ pkgs
, inputs
, options
, lib
, ...
}:
let
  theme = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.primitivistical-grub;
in
{
  system.stateVersion = "25.05";
  hardware.bluetooth.enable = false;

  boot = {
    loader.grub = {
      enable = true;
      device = "/dev/sda";
      useOSProber = true;
      configurationLimit = 42;
      inherit theme;
    };

    plymouth = {
      enable = true;
      theme = "mac-style";
      themePackages = [ pkgs.mac-style-plymouth ];
    };
  };

  nixpkgs = {
    overlays = [ inputs.mac-style-plymouth.overlays.default ];
    config.allowUnfree = true;
  };

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
    spice-vdagentd.enable = true;
  };

  environment.systemPackages = with pkgs; [
    foot
    xdg-utils
  ];

  environment.sessionVariables = {
    GSK_RENDERER = "cairo";
    WLR_RENDERER_ALLOW_SOFTWARE = "1";
  };
}
