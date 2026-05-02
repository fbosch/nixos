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
          "192.168.1.0/24"
          "100.64.0.0/10"
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
