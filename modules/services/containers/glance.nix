_: {
  flake.modules.nixos."services/containers/glance" =
    { config
    , lib
    , ...
    }:
    let
      cfg = config.services.glance-container;
      configDir = if cfg.configDir != null then cfg.configDir else "${cfg.dataDir}/config";
      assetsDir = if cfg.assetsDir != null then cfg.assetsDir else "${configDir}/assets";
      # Only mount assets separately if it's not inside configDir
      assetsDirIsSubdir = lib.hasPrefix "${configDir}/" assetsDir;
      containersFile = ../../../secrets/containers.yaml;
      rootOnly = {
        mode = "0400";
      };
      wheelReadable = {
        mode = "0440";
        group = "wheel";
      };
      mkContainerSecrets =
        opts: names: lib.genAttrs names (_: lib.recursiveUpdate { sopsFile = containersFile; } opts);
    in
    {
      options.services.glance-container = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 8080;
          description = "Port for Glance web interface";
        };

        imageTag = lib.mkOption {
          type = lib.types.str;
          default = "latest";
          description = "Glance container image tag";
        };

        dataDir = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/glance";
          description = "Base directory for Glance data";
        };

        configDir = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Directory containing glance.yml (defaults to dataDir/config)";
        };

        assetsDir = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Directory for Glance assets (defaults to dataDir/assets)";
        };

        envFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Path to an optional environment file (for template variables)";
        };

        enableDockerSocket = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Mount the Podman socket for the containers widget";
        };

        cpus = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "2.0";
          description = "Number of CPUs to allocate to the container (e.g., '2.0' for 2 cores, '0.5' for half a core)";
        };

        memory = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "2g";
          description = "Memory limit for the container (e.g., '512m', '2g')";
        };

        memoryReservation = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "1g";
          description = "Memory soft limit - allows container to use more if available";
        };

        shmSize = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "64m";
          example = "128m";
          description = "Shared memory size for /dev/shm (can improve performance for cached operations)";
        };

        timezone = lib.mkOption {
          type = lib.types.str;
          default = "Europe/Copenhagen";
          example = "America/New_York";
          description = "Timezone for the Glance container (IANA timezone identifier)";
        };
      };

      config = {
        services.glance-container.envFile = lib.mkDefault (
          lib.attrByPath [ "sops" "templates" "glance-env" "path" ] null config
        );

        sops = {
          secrets = lib.mkMerge [
            (mkContainerSecrets rootOnly [
              "rpi-pihole-password-token"
              "synology-api-username"
              "synology-api-password"
              "linkwarden-access-token"
              "tailscale-api-key"
              "nextdns-profile-id"
              "nextdns-api-key"
              "speedtest-tracker-api-token"
            ])
            (mkContainerSecrets wheelReadable [
              "komodo-web-api-key"
              "komodo-web-api-secret"
              "portainer-api-key"
              "ha-access-token"
            ])
          ];

          templates."glance-env" = {
            content = ''
              KOMODO_URL=https://komodo.corvus-corax.synology.me
              KOMODO_API_KEY=${config.sops.placeholder.komodo-web-api-key}
              KOMODO_API_SECRET=${config.sops.placeholder.komodo-web-api-secret}
              PORTAINER_URL=https://portainer.corvus-corax.synology.me
              PORTAINER_API_KEY=${config.sops.placeholder.portainer-api-key}
              SYNOLOGY_URL=https://corvus-corax.synology.me
              SYNOLOGY_USERNAME=${config.sops.placeholder.synology-api-username}
              SYNOLOGY_PASSWORD=${config.sops.placeholder.synology-api-password}
              HASS_URL=https://ha.corvus-corax.synology.me
              HASS_API_KEY=${config.sops.placeholder.ha-access-token}
              LINKWARDEN_TOKEN=${config.sops.placeholder.linkwarden-access-token}
              PIHOLE_PASSWORD=${config.sops.placeholder.rpi-pihole-password-token}
              GITHUB_TOKEN=${config.sops.placeholder.github-token}
              TAILSCALE_API_KEY=${config.sops.placeholder.tailscale-api-key}
              GLUETUN_URL=https://gluetun.corvus-corax.synology.me
              GLUETUN_API_KEY=${config.sops.placeholder.gluetun-control-api-key}
              NEXTDNS_PROFILE_ID=${config.sops.placeholder.nextdns-profile-id}
              NEXTDNS_API_KEY=${config.sops.placeholder.nextdns-api-key}
              SPEEDTEST_URL=https://speedtest-tracker.corvus-corax.synology.me
              SPEEDTEST_TRACKER_API_TOKEN=${config.sops.placeholder.speedtest-tracker-api-token}
            '';
            mode = "0400";
          };
        };

        services.containerPorts = lib.mkAfter [
          {
            service = "glance-container";
            tcpPorts = [ cfg.port ];
          }
        ];
        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0755 root root -"
          "d ${configDir} 0755 root root -"
          "d ${assetsDir} 0755 root root -"
        ];

        environment.etc."containers/systemd/glance.container".text = ''
          [Unit]
          After=network-online.target
          Wants=network-online.target

          [Container]
          ContainerName=glance
          Image=glanceapp/glance:${cfg.imageTag}
          PublishPort=${toString cfg.port}:8080
          Volume=${configDir}:/app/config
          ${lib.optionalString (!assetsDirIsSubdir) "Volume=${assetsDir}:/app/assets"}
          Volume=/etc/localtime:/etc/localtime:ro
          Environment=TZ=${cfg.timezone}
          ${lib.optionalString cfg.enableDockerSocket "Volume=/run/podman/podman.sock:/run/podman/podman.sock:ro"}
          ${lib.optionalString cfg.enableDockerSocket "Environment=DOCKER_HOST=unix:///run/podman/podman.sock"}
          ${lib.optionalString (cfg.envFile != null) "EnvironmentFile=${lib.escapeShellArg cfg.envFile}"}
          ${lib.optionalString (cfg.cpus != null) "PodmanArgs=--cpus=${cfg.cpus}"}
          ${lib.optionalString (cfg.memory != null) "PodmanArgs=--memory=${cfg.memory}"}
          ${lib.optionalString (
            cfg.memoryReservation != null
          ) "PodmanArgs=--memory-reservation=${cfg.memoryReservation}"}
          ${lib.optionalString (cfg.shmSize != null) "PodmanArgs=--shm-size=${cfg.shmSize}"}
          LogDriver=journald
          LogOpt=tag=glance

          [Service]
          Restart=always
          RestartSec=10
          TimeoutStartSec=60

          [Install]
          WantedBy=multi-user.target
        '';

        networking.firewall.allowedTCPPorts = [ cfg.port ];
      };
    };
}
