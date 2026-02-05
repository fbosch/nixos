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

        komodo = {
          url = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Komodo Core URL (e.g., 'https://komodo.example.com')";
          };

          apiKey = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Komodo API Key (begins with 'K-...')";
          };

          apiSecret = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Komodo API Secret (begins with 'S-...')";
          };
        };
      };

      config = {
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
          ${lib.optionalString cfg.enableDockerSocket "Volume=/run/podman/podman.sock:/run/podman/podman.sock:ro"}
          ${lib.optionalString cfg.enableDockerSocket "Environment=DOCKER_HOST=unix:///run/podman/podman.sock"}
          ${lib.optionalString (cfg.komodo.url != null) "Environment=KOMODO_URL=${cfg.komodo.url}"}
          ${lib.optionalString (cfg.komodo.apiKey != null) "Environment=KOMODO_API_KEY=${cfg.komodo.apiKey}"}
          ${lib.optionalString (
            cfg.komodo.apiSecret != null
          ) "Environment=KOMODO_API_SECRET=${cfg.komodo.apiSecret}"}
          ${lib.optionalString (cfg.envFile != null) "EnvironmentFile=${lib.escapeShellArg cfg.envFile}"}
          LogDriver=journald
          LogOpt=tag=glance

          [Service]
          Restart=always
          RestartSec=10
          TimeoutStartSec=300

          [Install]
          WantedBy=multi-user.target
        '';

        networking.firewall.allowedTCPPorts = [ cfg.port ];
      };
    };
}
