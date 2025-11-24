{ pkgs
, inputs
, options
, lib
, ...
}:
let
  theme = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.primitivistical-grub;

  # Create GRUB splash matching Plymouth's visual layout
  # GRUB will stretch to fit screen, so create at common 4:3 ratio (1024x768)
  # which matches typical BIOS display modes better than 16:9
  plymouthSplash = pkgs.runCommand "grub-splash.png"
    { nativeBuildInputs = [ pkgs.imagemagick ]; }
    ''
      logo="${pkgs.mac-style-plymouth}/share/plymouth/themes/mac-style/images/header-image.png"
    
      # Create 1024x768 canvas (common GRUB resolution, 4:3 aspect ratio)
      # Position logo centered, matching Plymouth's layout
      magick -size 1024x768 xc:black -colorspace sRGB \
        \( "$logo" -colorspace sRGB \) -gravity center -composite \
        -type TrueColor -depth 8 -define png:color-type=2 \
        $out
    '';
in
{
  system.stateVersion = "25.05";
  hardware.bluetooth.enable = false;

  boot = {
    # Hide boot messages for clean splash screen experience
    consoleLogLevel = 3; # Show only errors and critical messages
    kernelParams = [
      "quiet" # Suppress most kernel messages
      "splash" # Enable splash screen
      "vt.global_cursor_default=0" # Hide cursor
      "udev.log_level=3" # Reduce udev verbosity
      "rd.systemd.show_status=auto" # Only show status on errors
      "rd.udev.log_level=3" # Reduce initrd udev verbosity
    ];

    loader.grub = {
      enable = true;
      device = "/dev/sda";
      useOSProber = true;
      configurationLimit = 42;
      inherit theme;
      splashImage = plymouthSplash; # NixOS logo on black background matching Plymouth theme
      gfxmodeBios = "1024x768,auto"; # Use 4:3 ratio to match splash image
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
