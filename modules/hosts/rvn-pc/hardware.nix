# Do not modify this file manually. It originates from nixos-generate-config
# and may be overwritten when hardware configuration is regenerated.
{
  flake.modules.nixos."hosts/rvn-pc/hardware" =
    { config
    , lib
    , hostMeta
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

      nixpkgs.hostPlatform = lib.mkDefault hostMeta.system;

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
          package = config.boot.kernelPackages.nvidiaPackages.new_feature;
          moduleParams = {
            nvidia = {
              disable_vrr_memclk_switch = 1;
            };
          };
        };

        keyboard.zsa.enable = true;
      };

      services.xserver.videoDrivers = [ "nvidia" ];
    };
}
