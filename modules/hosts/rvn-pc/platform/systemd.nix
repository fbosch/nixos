{
  flake.modules.nixos."hosts/rvn-pc/platform" =
    { lib, ... }:
    {
      systemd = {
        services = {
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
