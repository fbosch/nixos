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

    # Service-specific configuration (only overrides from defaults)
    services = lib.mkMerge [
      {
        fstrim.enable = true;

        ananicy.enable = true;

        # Use Prowlarr as the single indexer manager for *arr services.
        prowlarr = {
          enable = true;
          openFirewall = true;
        };

        tailscale.extraSetFlags = [
          "--relay-server-port=40000"
          "--accept-dns=false"
        ];

        # OpenMemory
        openmemory-container = {
          buildImages = true;
          dashboardApiUrl = "https://memory.corvus-corax.synology.me";
        };

        tinyproxy = {
          port = 8888;
          listenAddress = "0.0.0.0"; # Listen on all interfaces for Tailscale access
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

          # Enable HTTP proxy stealth mode
          httpProxy.stealth = true;

          # Enable control server for Glance integration
          controlServer.enable = true;
        };

        # Avoid interference with Gluetun by disabling host Mullvad daemon on this server.
        mullvad-vpn.enable = lib.mkForce false;

        plex.nginx.port = 32402;

        pihole-container.listenAddress = hostMeta.local;
        pihole-container.webPort = 8082;

        redlib-container = {
          # Performance tuning
          memory = "2g";
          cpuQuota = "600%";
          pidsLimit = 1024;

          # Enable nginx caching for better performance
          nginx = {
            enable = true;
            port = 8283;
            cacheSize = "500m";
            cacheTTL = "1h";
          };
        };

        helium-services-container = {
          proxyBaseUrl = "https://helium.corvus-corax.synology.me";
          httpPort = 8100;
        };

        glance-container = {
          configDir = "/home/${config.flake.meta.user.username}/.config/glance";
          # Resource allocation for better performance
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

        linkwarden-container = {
          port = 3100;
          nextauthUrl = "https://linkwarden.corvus-corax.synology.me";
          disableRegistration = true; # Set to true after first user registration
          # Performance tuning
          cpus = "2.0";
          memory = "4g";
          memoryReservation = "2g";
          shmSize = "256m"; # Important for PDF/screenshot generation
          # Meilisearch resource limits (was hitting OOM at 512m)
          meilisearch.memory = "1g";
        };

        rdtclient = {
          port = 6500;
          downloadPath = "/mnt/nas/downloads";
          tempDownloadPath = "/mnt/nas/downloads/rdtclient-temp";
          # dataPath defaults to /var/lib/rdtclient/data (local storage for DB)
          timezone = "Europe/Copenhagen";
          userId = 1000;
          groupId = 1000;
          cpus = "0.25";
          memory = "4g";
        };

        speedtest-tracker = {
          port = 8085;
          appUrl = "https://speedtest.corvus-corax.synology.me";
          puid = 1000;
          pgid = 1000;
        };

        onwatch-container = {
          port = 9211;
        };

        resolved = {
          enable = true;
          settings.Resolve.DNSStubListener = "no";
        };

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
      }
    ];
  };
}
