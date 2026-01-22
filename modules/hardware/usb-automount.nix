_: {
  flake.modules.nixos."hardware/usb-automount" = _: {
    # USB automounting services
    services.devmon.enable = true;
    services.gvfs.enable = true;
    services.udisks2.enable = true;
  };
}
