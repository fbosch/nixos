{
  flake.modules.nixos."hosts/rvn-srv/boot" =
    { pkgs, ... }:
    {
      boot = {
        kernelPackages = pkgs.linuxKernel.packages.linux_7_3;

        loader = {
          systemd-boot.enable = true;
          efi.canTouchEfiVariables = true;
        };

        kernelParams = [ "transparent_hugepage=madvise" ];
      };
    };
}
