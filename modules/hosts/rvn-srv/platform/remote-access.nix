{ config, ... }:
let
  adminHosts = config.flake.meta.hosts;
  nasAddress = config.flake.meta.nas.ipAddress;
in
{
  flake.modules.nixos."hosts/rvn-srv/platform" = {
    services = {
      tailscale.extraSetFlags = [
        "--relay-server-port=40000"
        "--accept-dns=false"
      ];

      fail2ban = {
        enable = true;
        maxretry = 5;
        bantime = "1h";
        bantime-increment.enable = true;
        ignoreIP = [
          "127.0.0.1/8"
          "::1"
          # Admin machines only.
          adminHosts.rvn-pc.local
          adminHosts.rvn-pc.tailscale
          adminHosts.rvn-mac.local
          adminHosts.rvn-mac.tailscale
          # Synology reverse proxy terminates public HTTPS for hosted services;
          # banning its source IP would cut off external access.
          nasAddress
        ];
      };

      openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PubkeyAuthentication = true;
        };
      };
    };
  };
}
