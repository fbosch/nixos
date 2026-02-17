{ inputs, config, ... }:
let
  hostMeta = {
    name = "rvn-srv";
    sshAlias = "srv";
    tailscale = "100.125.172.110";
    local = "192.168.1.46";
    sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJl/WCQsXEkE7em5A6d2Du2JAWngIPfA8sVuJP/9cuyq fbb@nixos";
    dnsServers = [
      "127.0.0.1"
      "192.168.1.202"
      "45.90.28.240"
      "45.90.30.240"
    ];
  };
in
{
  # rvn-srv: Dendritic host configuration for MSI Cubi server
  # Hardware: Intel-based mini PC
  # Role: Home server running Plex, Home Assistant, and container services

  flake = {
    # Host metadata
    meta.hosts = [ hostMeta ];

    modules.nixos."hosts/rvn-srv" =
      { pkgs, lib, ... }:
      {
        imports = config.flake.lib.resolve [
          # Server preset (users, security, development, shell, system, vpn)
          "presets/server"

          # system
          "secrets"
          "nas"
          "system/scheduled-suspend"
          "system/ananicy"

          # files
          "files/wakatime"

          # applications
          "applications/surge"

          # services
          "services/home-assistant"
          "services/atticd"
          "services/attic-client"
          "services/plex"
          "services/servarr"
          "services/tinyproxy"
          "services/wakapi"
          "services/freshrss"

          # containerized services
          "virtualization/podman"
          "services/containers/dozzle"
          "services/containers/gluetun"
          "services/containers/redlib"
          "services/containers/termix"
          "services/containers/glance"
          "services/containers/pihole"
          "services/containers/helium"
          "services/containers/komodo"
          # "services/containers/openmemory"
          "services/containers/linkwarden"
          "services/containers/rdtclient"
          "services/containers/speedtest-tracker"

          # validation
          "validation/container-port-conflicts"

          # hardware configuration
          ../../machines/msi-cubi/configuration.nix
          ../../machines/msi-cubi/hardware-configuration.nix
          inputs.nixos-hardware.nixosModules.common-cpu-intel
        ];

        # Home Manager configuration for user
        home-manager.users.${config.flake.meta.user.username} = {
          imports = config.flake.lib.resolveHm [
            # Server preset modules for Home Manager
            "users"
            "dotfiles"
            "security"
            "development"
            "shell"
            "applications/surge"

            # Secrets for home-manager context
            "secrets"
          ];

          services.surge = {
            autostart = true;
            settings = {
              general.default_download_dir = "/mnt/nas/downloads";
              connections.proxy_url = "http://127.0.0.1:8889";
            };
          };
        };

        # Kernel tuning for server workload
        security.apparmor = {
          enable = true;
          killUnconfinedConfinables = false;
          enableCache = false;
        };

        boot.kernel.sysctl = {
          "vm.swappiness" = 10; # Only swap when critically low on RAM
          "vm.vfs_cache_pressure" = 50; # Keep filesystem cache longer
          "vm.dirty_ratio" = 15; # Start sync at 15% RAM dirty
          "vm.dirty_background_ratio" = 10; # Background writes at 10%

          # TCP optimizations for nginx/web serving (conservative values)
          "net.core.somaxconn" = 4096; # Increase max connection backlog
          "net.ipv4.tcp_fastopen" = 3; # Enable TCP Fast Open (client + server)
          "net.ipv4.tcp_keepalive_time" = 600; # Keep connections alive longer
          "net.ipv4.tcp_keepalive_intvl" = 60;
          "net.ipv4.tcp_keepalive_probes" = 3;
          "net.core.netdev_max_backlog" = 5000; # Increase network device backlog
        };

        # Scheduled suspend/wake for power savings
        powerManagement.scheduledSuspend = {
          schedules = {
            weekday = {
              suspendTime = "00:30";
              wakeTime = "06:00";
              days = "Mon,Tue,Wed,Thu";
            };
            friday = {
              suspendTime = "02:00";
              wakeTime = "06:00";
              days = "Fri";
            };
            weekend = {
              suspendTime = "02:00";
              wakeTime = "08:00";
              days = "Sat,Sun";
            };
          };
        };

        # Service-specific configuration (only overrides from defaults)
        services = lib.mkMerge [
          {
            ananicy.enable = true;

            # OpenMemory
            # openmemory-container = {
            #   buildImages = true;
            #   dashboardApiUrl = "https://memory.corvus-corax.synology.me";
            #   openaiApiKey = lib.attrByPath [ "sops" "placeholder" "openai-api-key" ] "" config;
            #   embeddings = "openai";
            #   embeddingFallback = "synthetic";
            #   tier = "deep";
            # };

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
              enable = true;
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
            };

            speedtest-tracker = {
              enable = true;
              port = 8085;
              appUrl = "https://speedtest.corvus-corax.synology.me";
              puid = 1000;
              pgid = 1000;
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

            openssh.settings = {
              PasswordAuthentication = false;
              KbdInteractiveAuthentication = false;
              PubkeyAuthentication = true;
            };
          }
        ];

        # Networking configuration
        networking = {
          # Open port for uptime-kuma
          firewall.allowedTCPPorts = [ 3001 ];

          # Enable systemd-networkd for bonding support
          useNetworkd = true;
          useDHCP = false; # Disable legacy DHCP
          nameservers = hostMeta.dnsServers;
        };

        systemd.network.enable = true;

        # NIC bonding configuration for dual ethernet ports
        # Using balance-rr (no switch config needed)
        systemd.network = {
          netdevs."10-bond0" = {
            netdevConfig = {
              Kind = "bond";
              Name = "bond0";
            };
            bondConfig = {
              Mode = "balance-rr"; # Round-robin (no switch config needed)
              TransmitHashPolicy = "layer3+4"; # Hash by IP+port
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

  };
}
