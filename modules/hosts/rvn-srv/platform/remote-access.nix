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
          # Admin machines only (see flake.meta.hosts): rvn-pc and rvn-mac.
          "192.168.1.169"
          "100.124.57.90"
          "192.168.167.54"
          "100.118.36.81"
          # Synology reverse proxy terminates public HTTPS for hosted services;
          # banning its source IP would cut off external access.
          "192.168.1.2"
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
