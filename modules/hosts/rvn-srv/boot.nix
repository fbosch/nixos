{
  flake.modules.nixos."hosts/rvn-srv/boot" = {
    boot = {
      loader = {
        systemd-boot.enable = true;
        efi.canTouchEfiVariables = true;
      };

      kernelParams = [ "transparent_hugepage=madvise" ];
    };
  };
}
