{ config, lib, ... }:
{
  flake.modules.nixos."hosts/rvn-pc/platform" = { hostMeta, ... }: {
    networking = {
      hostName = "rvn-pc";
      networkmanager = {
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
          #
          # DNS flow (strict-order):
          #
          #   query 127.0.0.1:53
          #          │
          #          v
          #   ┌──────────────────┐   Synology zone
          #   │     dnsmasq      │──────────────────> 192.168.1.2 (local answer)
          #   └────────┬─────────┘
          #            │ everything else, in order
          #            v
          #   192.168.1.46 ──fail──> 192.168.1.202 ──fail──> 127.0.0.1:5553
          #                                                       │
          #                                                       v
          #                                                 NextDNS (DoH)
          #
          server = hostMeta.dnsServers ++ [ "127.0.0.1#5553" ];
        };
      };

      nextdns = {
        enable = true;
        listenAddress = "127.0.0.1:5553";
      };
    };
  };
}
