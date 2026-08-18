{ config, lib, ... }:
{
  flake.modules.nixos."hosts/rvn-pc/platform" = _: {
    networking = {
      hostName = "rvn-pc";
      networkmanager = {
        enable = true;
        # Keep DHCP-provided DNS out of resolv.conf so all lookups use dnsmasq.
        dns = lib.mkForce "none";
      };
      # Single funnel through dnsmasq: the Synology zone is answered locally,
      # everything else resolves via NextDNS (DoH through the Mullvad tunnel).
      nameservers = [ "127.0.0.1" ];
      timeServers = [ "time.nist.gov" ];
    };
    services.tailscale.extraSetFlags = [ "--accept-dns=false" ];

    services = {
      dnsmasq = {
        enable = true;
        resolveLocalQueries = false;
        settings = {
          no-resolv = true;
          strict-order = true;
          listen-address = "127.0.0.1";
          bind-interfaces = true;
          log-queries = "extra";
          address = [
            "/${config.flake.meta.synology.domain}/${config.flake.meta.nas.ipAddress}"
          ];
          server = [ "127.0.0.1#5553" ];
        };
      };

      nextdns = {
        enable = true;
        listenAddress = "127.0.0.1:5553";
      };
    };
  };
}
