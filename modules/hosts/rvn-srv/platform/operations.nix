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
      openmemory-container = {
        buildImages = true;
        dashboardApiUrl = "https://memory.corvus-corax.synology.me";
      };

      pihole-container = {
        listenAddress = hostMeta.local;
        webPort = 8082;
      };

      helium-services-container = {
        proxyBaseUrl = "https://helium.corvus-corax.synology.me";
        httpPort = 8100;
      };

      glance-container = {
        configDir = "/home/${config.flake.meta.user.username}/.config/glance";
        cpus = "2.0";
        memory = "1g";
        memoryReservation = "512m";
        shmSize = "128m";
      };

      dozzle = {
        port = 8090;
        hostname = "rvn-srv";
        noAnalytics = true;
      };

      komodo = {
        core.host = "https://komodo.corvus-corax.synology.me";
        core.allowSignups = false;
        # periphery.requirePasskey = false;
      };

      uptime-kuma = {
        enable = true;
        settings.HOST = "0.0.0.0";
      };

      glances = {
        enable = true;
        openFirewall = true;
        extraArgs = [ "-w" ];
      };

      speedtest-tracker = {
        port = 8085;
        appUrl = "https://speedtest.corvus-corax.synology.me";
        puid = 1000;
        pgid = 1000;
      };

      onwatch-container.port = 9211;

      resolved = {
        enable = true;
        settings.Resolve.DNSStubListener = "no";
      };

      nextdns = {
        enable = true;
      };
    };

    services.exposedPorts = lib.mkAfter [
      {
        service = "glances";
        tcpPorts = [ 61208 ];
      }
    ];
  };
}
