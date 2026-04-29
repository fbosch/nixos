# Do not modify this file manually. It originates from nixos-generate-config
# and may be overwritten when hardware configuration is regenerated.
{
  flake.modules.nixos."hosts/rvn-pc/hardware" =
    { config
    , lib
    , pkgs
    , modulesPath
    , ...
    }:
    {
      imports = [
        (modulesPath + "/installer/scan/not-detected.nix")
      ];

      boot = {
        initrd = {
          availableKernelModules = [
            "xhci_pci"
            "ahci"
            "nvme"
            "usbhid"
            "usb_storage"
            "sd_mod"
          ];
          kernelModules = [
            "nvidia"
            "nvidia_modeset"
            "nvidia_drm"
          ];
        };
        kernelModules = [ "kvm-intel" ];
        extraModulePackages = [ ];
      };

      fileSystems."/" = {
        device = "/dev/disk/by-uuid/68d6a3ae-c19a-4cf0-befe-c6531394b4a4";
        fsType = "ext4";
      };

      fileSystems."/boot" = {
        device = "/dev/disk/by-uuid/3C1F-3077";
        fsType = "vfat";
        options = [
          "fmask=0077"
          "dmask=0077"
        ];
      };

      swapDevices = [ ];

      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

      environment.systemPackages = with pkgs; [ keymapp ];

      hardware = {
        cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

        # Graphics configuration with HDR support
        graphics = {
          enable = true;
          enable32Bit = true; # For 32-bit applications
          extraPackages = with pkgs; [
            nvidia-vaapi-driver
            libva-vdpau-driver
            libvdpau-va-gl
          ];
        };

        nvidia = {
          modesetting.enable = true;
          powerManagement.enable = true;
          powerManagement.finegrained = false;
          open = false;
          nvidiaSettings = true;
          nvidiaPersistenced = true; # Keep GPU initialized for better performance
          package = config.boot.kernelPackages.nvidiaPackages.stable;
        };

        keyboard.zsa.enable = true;
      };

      services.xserver.videoDrivers = [ "nvidia" ];
    };
}
