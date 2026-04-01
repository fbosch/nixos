{
  flake.modules.nixos."hosts/rvn-pc/systemd" =
    { lib, ... }:
    {
      # Keep these available for manual start/socket activation, but do not auto-start at boot.
      systemd.services = {
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
}
