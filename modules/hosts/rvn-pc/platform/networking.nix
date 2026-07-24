{ config
, lib
, ...
}:
let
  hostMeta = config.flake.lib.hostMeta "rvn-pc";
in
{
  flake.modules.nixos."hosts/rvn-pc/platform" = {
    assertions = [
      {
        assertion = hostMeta != null;
        message = "Missing host metadata for rvn-pc";
      }
    ];
    networking = {
      hostName = "rvn-pc";
      networkmanager = {
        enable = true;
        # Keep DHCP-provided DNS out of resolv.conf so all lookups use dnsmasq.
        dns = "none";
      };
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
