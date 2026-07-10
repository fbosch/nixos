{ config
, lib
, ...
}:
let
  hostMeta = lib.findFirst (host: host.name == "rvn-srv") null config.flake.meta.hosts;
in
{
  flake.modules.nixos."hosts/rvn-srv/platform" = {
    assertions = [
      {
        assertion = hostMeta != null;
        message = "Missing host metadata for rvn-srv";
      }
    ];

    networking = {
      hostName = "rvn-srv";
      networkmanager.enable = false;

      firewall.allowedUDPPorts = [ 40000 ];

      # Enable systemd-networkd for bonding support
      useNetworkd = true;
      useDHCP = false;
      nameservers = hostMeta.dnsServers;
    };

    services.exposedPorts = lib.mkAfter [
      {
        service = "tailscale-relay";
        udpPorts = [ 40000 ];
      }
    ];

    systemd.network = {
      enable = true;

      netdevs."10-bond0" = {
        netdevConfig = {
          Kind = "bond";
          Name = "bond0";
        };
        bondConfig = {
          Mode = "balance-xor";
          TransmitHashPolicy = "layer3+4";
          MIIMonitorSec = "100ms";
        };
      };

      networks = {
        "30-enp2s0" = {
          matchConfig.Name = "enp2s0";
          networkConfig.Bond = "bond0";
        };

        "30-enp3s0" = {
          matchConfig.Name = "enp3s0";
          networkConfig.Bond = "bond0";
        };

        "40-bond0" = {
          matchConfig.Name = "bond0";
          linkConfig.RequiredForOnline = "carrier";
          networkConfig = {
            Address = "192.168.1.46/24";
            Gateway = "192.168.1.1";
            DNS = hostMeta.dnsServers;
            LinkLocalAddressing = "no";
          };
        };
      };
    };
  };
}
