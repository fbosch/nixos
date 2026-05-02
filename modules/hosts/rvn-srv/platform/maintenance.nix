{
  flake.modules.nixos."hosts/rvn-srv/platform" = {
    services = {
      fstrim.enable = true;
      ananicy.enable = true;
    };
  };
}
