# Do not modify this file manually. It originates from nixos-generate-config
# and may be overwritten when hardware configuration is regenerated.
{ lib, ... }:
{
  flake.modules.nixos."hosts/rvn-vm/hardware" =
    { hostMeta, ... }:
    {
      imports = [ ];

      boot = {
        initrd = {
          availableKernelModules = [
            "ata_piix"
            "ohci_pci"
            "ehci_pci"
            "ahci"
            "sd_mod"
            "sr_mod"
          ];
          kernelModules = [ ];
        };
        kernelModules = [ ];
        extraModulePackages = [ ];
      };

      fileSystems."/" = {
        device = "/dev/disk/by-uuid/e845efb7-148c-40c7-ba4c-e4d1f03e0ab6";
        fsType = "ext4";
      };

      swapDevices = [{ device = "/dev/disk/by-uuid/5bc8db14-f547-4119-9705-ae8b5b5bf364"; }];

      networking.useDHCP = lib.mkDefault true;

      nixpkgs.hostPlatform = lib.mkDefault hostMeta.system;

      virtualisation.virtualbox.guest = {
        enable = true;
        dragAndDrop = true;
        clipboard = true;
      };
    };
}
