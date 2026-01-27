# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').

{ pkgs
, inputs
, options
, ...
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
      # NVIDIA suspend support
      "nvidia.NVreg_PreserveVideoMemoryAllocations=1" # Preserve video memory allocations for suspend
      # Use deep suspend mode for better NVIDIA compatibility
      "mem_sleep_default=deep" # More reliable suspend with NVIDIA GPUs
      # Fix framebuffer console artifacts
      "fbcon=nodefer" # Prevent deferred framebuffer console takeover
    ];

    # Optimize tmpfs usage for 32GB RAM system
    tmp = {
      useTmpfs = true;
      tmpfsSize = "8G"; # ~25% of RAM for temporary files
    };

    loader = {
      grub = {
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

      efi.canTouchEfiVariables = true;

      grub2-theme = {
        enable = true;
        theme = "whitesur";
        icon = "white";
        screen = "1080p";
        footer = true;
        splashImage = ./../../assets/grub-backgrounds/black.jpg;
      };
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

  # Configure console keymap
  console.keyMap = "dk-latin1";

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

}
