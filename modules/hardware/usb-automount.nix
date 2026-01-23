_: {
  flake.modules.nixos."hardware/usb-automount" = _: {
    # USB automounting services
    services = {
      devmon.enable = true;
      gvfs.enable = true;
      udisks2.enable = true;
    };
  };
}
