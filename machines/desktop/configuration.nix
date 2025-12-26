# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').

{
  config,
  pkgs,
  inputs,
  options,
  ...
}:
{

  system.stateVersion = "25.11"; # Did you read the comment?
  hardware.bluetooth.enable = false;

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

    # Optimize tmpfs usage for 32GB RAM system
    tmp = {
      useTmpfs = true;
      tmpfsSize = "8G"; # ~25% of RAM for temporary files
    };

    loader.grub = {
      enable = true;
      device = "nodev";
      efiSupport = true;
      useOSProber = true;
      configurationLimit = 42;
      extraConfig = ''
        # Use maximum supported resolution (1080p)
        set gfxmode=1920x1080
        insmod all_video
        insmod gfxterm
        terminal_output gfxterm
      '';
    };

    loader.efi.canTouchEfiVariables = true;

    loader.grub2-theme = {
      enable = true;
      theme = "whitesur";
      icon = "white";
      screen = "1080p";
      footer = true;
      splashImage = ./../../assets/grub-backgrounds/black.jpg;
    };

    plymouth = {
      enable = true;
      theme = "monoarch-refined";
      themePackages = [ inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.monoarch-plymouth ];
    };
  };

  nixpkgs = {
    config.allowUnfree = true;
  };

  services = {
    upower.enable = true;
    dbus.enable = true;
    timesyncd.enable = true;
    ananicy = {
      enable = true;
      package = pkgs.ananicy-cpp;
      rulesProvider = pkgs.ananicy-rules-cachyos;
    };
    spice-vdagentd.enable = true;
    system76-scheduler.enable = true;
  };

  networking = {
    hostName = "rvn-pc";
    networkmanager.enable = true;
    timeServers = options.networking.timeServers.default ++ [ "time.nist.gov" ];
  };

  zramSwap.enable = true;
  security.polkit.enable = true;

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

}
