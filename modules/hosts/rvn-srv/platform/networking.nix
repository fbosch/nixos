{ lib, ... }:
{
  flake.modules.nixos."hosts/rvn-srv/platform" = { hostMeta, ... }: {
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

    # Bonded network topology:
    #
    #   enp2s0 ─┐
    #           ├──> bond0 (balance-xor, layer3+4 hash)
    #   enp3s0 ─┘           │
    #                       ├──> 192.168.1.46/24
    #                       ├──> gateway 192.168.1.1
    #                       └──> host DNS servers
    #
    #   bond0 carrier is required before the host is considered online.
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
