_: {
  flake.modules.nixos."services/containers/komodo" =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.services.komodo;
      effectivePasskeyFile = lib.attrByPath [ "sops" "secrets" "komodo-passkey" "path" ] null config;
      usePasskey = cfg.periphery.requirePasskey && effectivePasskeyFile != null;
      effectiveAdminPasswordFile = lib.attrByPath [
        "sops"
        "secrets"
        "komodo-admin-password"
        "path"
      ] null config;
      useAdminBootstrap = cfg.core.initAdminUsername != null && effectiveAdminPasswordFile != null;
      composeEnvPath = "/etc/komodo/compose.env";
      peripheryConfigPath = "/etc/komodo/periphery.toml";
      composeEnvTemplateText =
        let
          lines = builtins.filter (line: line != null) [
            "COMPOSE_KOMODO_IMAGE_TAG=${cfg.core.imageTag}"
            "KOMODO_DB_USERNAME=${config.sops.placeholder.komodo-db-username}"
            "KOMODO_DB_PASSWORD=${config.sops.placeholder.komodo-db-password}"
            "MONGO_INITDB_ROOT_USERNAME=${config.sops.placeholder.komodo-db-username}"
            "MONGO_INITDB_ROOT_PASSWORD=${config.sops.placeholder.komodo-db-password}"
            "KOMODO_HOST=${cfg.core.host}"
            "KOMODO_TITLE=Komodo"
            "KOMODO_LOCAL_AUTH=true"
            "KOMODO_DISABLE_USER_REGISTRATION=${if cfg.core.allowSignups then "false" else "true"}"
            "KOMODO_DATABASE_ADDRESS=komodo-mongo:27017"
            "KOMODO_DATABASE_USERNAME=${config.sops.placeholder.komodo-db-username}"
            "KOMODO_DATABASE_PASSWORD=${config.sops.placeholder.komodo-db-password}"
            (if useAdminBootstrap then "KOMODO_INIT_ADMIN_USERNAME=${cfg.core.initAdminUsername}" else null)
            (
              if useAdminBootstrap then "KOMODO_INIT_ADMIN_PASSWORD_FILE=${effectiveAdminPasswordFile}" else null
            )
            (if usePasskey then "KOMODO_PASSKEY_FILE=${effectivePasskeyFile}" else null)
          ];
        in
        lib.concatStringsSep "\n" lines + "\n";
      peripheryConfigText =
        let
          lines = [
            "port = 8120"
            "bind_ip = \"0.0.0.0\""
            "root_directory = \"/var/lib/komodo-periphery\""
            "ssl_enabled = false"
          ];
        in
        lib.concatStringsSep "\n" lines + "\n";
    in
    {
      options.services.komodo = {
        core = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to enable Komodo Core web UI";
          };

          port = lib.mkOption {
            type = lib.types.port;
            default = 9120;
            description = "Port for Komodo Core web interface";
          };

          host = lib.mkOption {
            type = lib.types.str;
            default = "http://localhost:9120";
            description = "Public URL for Komodo Core";
          };

          allowSignups = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to allow user self-registration";
          };

          initAdminUsername = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Initial admin username to bootstrap when signups are disabled";
          };

          imageTag = lib.mkOption {
            type = lib.types.str;
            default = "latest";
            description = "Komodo Core Docker image tag";
          };
        };

        periphery = {
          requirePasskey = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether Periphery requires a passkey for API access";
          };
        };
      };

      config = {
        # Disable Docker since komodo-periphery enables it by default
        # We use Podman with docker-compat instead (from virtualization/podman.nix)
        virtualisation.docker.enable = lib.mkForce false;

        # Komodo Core via Quadlet
        environment.etc = {
          # Link the SOPS-rendered env file to /etc/komodo/compose.env
          "komodo/compose.env" = lib.mkIf cfg.core.enable {
            source = config.sops.templates."komodo-compose-env".path;
            mode = "0400";
          };

          "komodo/periphery.toml" = lib.mkIf cfg.core.enable {
            text = peripheryConfigText;
            mode = "0400";
          };

          "containers/systemd/komodo.network" = lib.mkIf cfg.core.enable {
            text = ''
              [Network]
              NetworkName=komodo
            '';
          };

          "containers/systemd/komodo-mongo.container" = lib.mkIf cfg.core.enable {
            text = ''
              [Unit]
              After=network-online.target
              Wants=network-online.target

              [Container]
              ContainerName=komodo-mongo
              Image=mongo:latest
              Exec=--quiet --wiredTigerCacheSizeGB 0.25
              Network=komodo.network
              EnvironmentFile=${composeEnvPath}
              Volume=komodo-mongo-data.volume:/data/db
              Volume=komodo-mongo-config.volume:/data/configdb
              Memory=2g
              PidsLimit=1000
              Ulimit=nofile=2048:4096
              LogDriver=journald
              LogOpt=tag=komodo-mongo

              [Service]
              Restart=always
              RestartSec=10
              CPUQuota=200%
              TimeoutStartSec=300

              [Install]
              WantedBy=multi-user.target
            '';
          };

          "containers/systemd/komodo-core.container" = lib.mkIf cfg.core.enable {
            text = ''
              [Unit]
              After=network-online.target komodo-mongo.service
              Wants=network-online.target
              Requires=komodo-mongo.service

              [Container]
              ContainerName=komodo-core
              Image=ghcr.io/moghtech/komodo-core:${cfg.core.imageTag}
              Network=komodo.network
              PublishPort=${toString cfg.core.port}:9120
              EnvironmentFile=${composeEnvPath}
              Environment=KOMODO_DATABASE_ADDRESS=komodo-mongo:27017
              Volume=/var/lib/komodo/backups:/backups
              ${lib.optionalString (effectivePasskeyFile != null) ''
                Volume=${effectivePasskeyFile}:${effectivePasskeyFile}:ro
              ''}
              Memory=512m
              PidsLimit=500
              Ulimit=nofile=2048:4096
              LogDriver=journald
              LogOpt=tag=komodo-core

              [Service]
              Restart=always
              RestartSec=10
              CPUQuota=100%
              TimeoutStartSec=300

              [Install]
              WantedBy=multi-user.target
            '';
          };

          "containers/systemd/komodo-periphery.container" = lib.mkIf cfg.core.enable {
            text = ''
              [Unit]
              After=network-online.target
              Wants=network-online.target

              [Container]
              ContainerName=komodo-periphery
              Image=ghcr.io/moghtech/komodo-periphery:latest
              Network=komodo.network
              PublishPort=8120:8120
              GroupAdd=991
              Exec=periphery --config-path ${peripheryConfigPath}
              Environment=DOCKER_HOST=unix:///run/podman/podman.sock
              ${lib.optionalString usePasskey ''
                Environment=PERIPHERY_PASSKEYS_FILE=${effectivePasskeyFile}
              ''}
              Volume=/run/podman/podman.sock:/run/podman/podman.sock
              Volume=/var/lib/komodo-periphery:/var/lib/komodo-periphery
              Volume=${peripheryConfigPath}:${peripheryConfigPath}:ro
              ${lib.optionalString (effectivePasskeyFile != null) ''
                Volume=${effectivePasskeyFile}:${effectivePasskeyFile}:ro
              ''}
              Memory=512m
              PidsLimit=500
              Ulimit=nofile=2048:4096
              LogDriver=journald
              LogOpt=tag=komodo-periphery

              [Service]
              Restart=always
              RestartSec=10
              CPUQuota=100%
              TimeoutStartSec=300

              [Install]
              WantedBy=multi-user.target
            '';
          };

          "containers/systemd/komodo-mongo-data.volume" = lib.mkIf cfg.core.enable {
            text = ''
              [Volume]
              VolumeName=komodo-mongo-data
            '';
          };

          "containers/systemd/komodo-mongo-config.volume" = lib.mkIf cfg.core.enable {
            text = ''
              [Volume]
              VolumeName=komodo-mongo-config
            '';
          };
        };

        systemd = {
          tmpfiles.rules = lib.mkIf cfg.core.enable [
            "d /var/lib/komodo 0750 root root -"
            "d /var/lib/komodo/backups 0750 root root -"
            "d /var/lib/komodo-periphery 0750 root root -"
          ];
        };

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.core.enable [
          cfg.core.port
          8120
        ];

        # Wire passkey and secrets through sops
        sops = {
          secrets = {
            komodo-passkey = lib.mkIf cfg.periphery.requirePasskey {
              mode = "0440";
            };

            komodo-db-username = {
              mode = "0400";
            };

            komodo-db-password = {
              mode = "0400";
            };

            komodo-admin-password = lib.mkIf (cfg.core.initAdminUsername != null) {
              mode = "0400";
            };
          };

          templates."komodo-compose-env" = lib.mkIf cfg.core.enable {
            content = composeEnvTemplateText;
            mode = "0400";
          };
        };
      };
    };
}
