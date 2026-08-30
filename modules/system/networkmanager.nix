{
  flake.modules.nixos."system/networkmanager" = { lib, ... }: {
    networking.networkmanager.enable = lib.mkDefault true;

    # NetworkManager ships initrd-only variants in the same package.
    # Disabled declarations mask those package units in stage 2 only.
    systemd.services = {
      NetworkManager-config-initrd.enable = false;
      NetworkManager-initrd.enable = false;
      NetworkManager-wait-online-initrd.enable = false;

      # Desktop hosts do not need to block boot on network-online.
      NetworkManager-wait-online.enable = lib.mkForce false;
    };
  };
}
