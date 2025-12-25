# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').

{
  config,
  pkgs,
  inputs,
  ...
}:
let
  theme = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.primitivistical-grub;

  # Create GRUB splash matching Plymouth's visual layout
  # GRUB will stretch to fit screen, so create at common 4:3 ratio (1024x768)
  # which matches typical BIOS display modes better than 16:9
  plymouthSplash =
    pkgs.runCommand "grub-splash.png"
      {
        nativeBuildInputs = [ pkgs.imagemagick ];
      }
      ''
        logo="${inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.monoarch-plymouth}/share/plymouth/themes/monoarch-refined/images/logo.png"

        # Create 1024x768 canvas (common GRUB resolution, 4:3 aspect ratio)
        # Position logo centered, matching Plymouth's layout
        magick -size 1024x768 xc:black -colorspace sRGB \
          \( "$logo" -colorspace sRGB \) -gravity center -composite \
          -type TrueColor -depth 8 -define png:color-type=2 \
          $out
      '';
in

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

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
      # HDR support for NVIDIA
      "nvidia_drm.modeset=1" # Enable modesetting (required for HDR)
      "nvidia.NVreg_EnableGpuFirmware=0" # Improve compatibility
    ];

    loader.grub = {
      enable = true;
      device = "nodev";
      efiSupport = true;
      useOSProber = true;
      configurationLimit = 42;
      inherit theme;
      splashImage = plymouthSplash; # NixOS logo on black background matching Plymouth theme
      gfxmodeEfi = "1024x768,auto"; # Use 4:3 ratio to match splash image
    };
    loader.efi.canTouchEfiVariables = true;

    plymouth = {
      enable = true;
      theme = "monoarch-refined";
      themePackages = [ inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.monoarch-plymouth ];
    };
  };

  nixpkgs = {
    config.allowUnfree = true;
  };

  networking.hostName = "rvn-pc"; # Define your hostname.
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Copenhagen";

  # Configure console keymap
  console.keyMap = "dk-latin1";

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.fbb = {
    isNormalUser = true;
    description = "Frederik Bosch";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    packages = with pkgs; [ ];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    wget
    vim
    neovim
  ];

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?

}
