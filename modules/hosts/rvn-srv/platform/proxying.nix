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

    services = {
      tinyproxy = {
        port = 8888;
        listenAddress = "0.0.0.0"; # Listen on all interfaces for Tailscale access.
        allowedClients = [
          "192.168.1.0/24"
          "100.64.0.0/10" # Tailscale CGNAT range
        ];
        anonymize = false;
      };

      gluetun-container = {
        port = 8889;
        listenAddresses = [
          "127.0.0.1"
          hostMeta.local
          hostMeta.tailscale
        ];
        serverCountries = [ "Denmark" ];
        httpProxy.stealth = true;
        controlServer.enable = true;
      };

      # Avoid interference with Gluetun by disabling host Mullvad daemon on this server.
      mullvad-vpn.enable = lib.mkForce false;
    };

    services.exposedPorts = lib.mkAfter [
      {
        service = "tinyproxy";
        tcpPorts = [ 8888 ];
      }
    ];
  };
}
