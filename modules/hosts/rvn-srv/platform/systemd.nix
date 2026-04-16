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

    systemd.network = {
      enable = true;

      # NIC bonding configuration for dual ethernet ports
      netdevs."10-bond0" = {
        netdevConfig = {
          Kind = "bond";
          Name = "bond0";
        };
        bondConfig = {
          Mode = "balance-xor"; # Per-flow XOR hash, no packet reordering
          TransmitHashPolicy = "layer3+4"; # Hash by IP+port (used by balance-xor)
          MIIMonitorSec = "100ms"; # Link monitoring
        };
      };

      networks = {
        # Assign enp2s0 to bond
        "30-enp2s0" = {
          matchConfig.Name = "enp2s0";
          networkConfig.Bond = "bond0";
        };

        # Assign enp3s0 to bond
        "30-enp3s0" = {
          matchConfig.Name = "enp3s0";
          networkConfig.Bond = "bond0";
        };

        # Configure bond0 interface with static IP
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
