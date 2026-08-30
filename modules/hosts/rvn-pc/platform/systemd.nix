{
  flake.modules.nixos."hosts/rvn-pc/platform" =
    { lib, ... }:
    {
      systemd = {
        # NetworkManager ships initrd-only variants in the same package. Mask
        # them in stage 2 so systemd does not see a duplicate D-Bus owner.
        suppressedSystemUnits = [
          "NetworkManager-config-initrd.service"
          "NetworkManager-initrd.service"
          "NetworkManager-wait-online-initrd.service"
        ];

        # Keep these available for manual start/socket activation, but do not auto-start at boot.
        services = {
          # Desktop host: avoid blocking boot on network-online when not required.
          NetworkManager-wait-online.enable = lib.mkForce false;

          # tailscaled-set pulls in tailscaled during boot; keep both manual.
          tailscaled-set.wantedBy = lib.mkForce [ ];
          tailscaled.wantedBy = lib.mkForce [ ];

          # libvirt-guests starts libvirtd at boot; keep virtualization services manual.
          libvirt-guests.wantedBy = lib.mkForce [ ];
          libvirtd.wantedBy = lib.mkForce [ ];
        };
      };
    };
}
