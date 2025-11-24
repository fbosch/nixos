{ pkgs
, inputs
, options
, lib
, system
, ...
}:
let
  theme = inputs.self.packages.${system}.primitivistical-grub;

  # Create GRUB splash with Plymouth logo positioned exactly like Plymouth (59% vertical)
  plymouthSplash = pkgs.runCommand "grub-splash.png"
    { nativeBuildInputs = [ pkgs.imagemagick ]; }
    ''
      # Use Plymouth's exact header image, positioned to match visual appearance
      logo="${pkgs.mac-style-plymouth}/share/plymouth/themes/mac-style/images/header-image.png"
    
      # Plymouth has both logo and progress bar at 59% vertical (they overlap)
      # Move logo up to leave space for where progress bar would be
      # Logo: 245px tall, place it so bottom is just above 59% line
      # 59% of 1080 = 636, logo height 245, so top = 636 - 245 - 30 (gap) = 361
      magick -size 1920x1080 xc:black -colorspace sRGB \
        \( "$logo" -colorspace sRGB \) -gravity north -geometry +0+361 -composite \
        -type TrueColor -depth 8 -define png:color-type=2 \
        $out
    '';
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
      splashImage = plymouthSplash; # NixOS logo on black background matching Plymouth theme
      gfxmodeBios = "1920x1080,1024x768,auto"; # Try 1920x1080, fallback to 1024x768, then auto
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
