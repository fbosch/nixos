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

      # Open port for uptime-kuma
      firewall.allowedTCPPorts = [ 3001 ];
      firewall.allowedUDPPorts = [ 40000 ];

      # Enable systemd-networkd for bonding support
      useNetworkd = true;
      useDHCP = false;
      nameservers = hostMeta.dnsServers;
    };

    services.exposedPorts = lib.mkAfter [
      {
        service = "uptime-kuma";
        tcpPorts = [ 3001 ];
      }
      {
        service = "tailscale-relay";
        udpPorts = [ 40000 ];
      }
    ];
  };
}
