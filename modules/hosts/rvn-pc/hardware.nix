# Do not modify this file manually. It originates from nixos-generate-config
# and may be overwritten when hardware configuration is regenerated.
{
  flake.modules.nixos."hosts/rvn-pc/hardware" =
    { config
    , lib
    , hostMeta
    , pkgs
    , modulesPath
    , options
    , ...
    }:
    let
      diskoEnabled = lib.hasAttrByPath [ "disko" "enableConfig" ] options && config.disko.enableConfig;
    in
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

      # Disko owns the fresh-install mount and swap definitions when imported.
      fileSystems = lib.mkIf (!diskoEnabled) {
        "/" = {
          device = "/dev/disk/by-uuid/68d6a3ae-c19a-4cf0-befe-c6531394b4a4";
          fsType = "ext4";
        };

        "/boot" = {
          device = "/dev/disk/by-uuid/3C1F-3077";
          fsType = "vfat";
          options = [
            "fmask=0077"
            "dmask=0077"
          ];
        };
      };

      swapDevices = lib.mkIf (!diskoEnabled) [ ];

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
