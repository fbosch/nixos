_: {
  # Linkwarden - Self-hosted collaborative bookmark manager
  # https://github.com/linkwarden/linkwarden
  #
  # This module deploys Linkwarden with PostgreSQL and Meilisearch using Podman Quadlet.
  #
  # SETUP:
  # 1. Generate secrets:
  #    - postgresPassword: openssl rand -base64 32
  #    - nextauthSecret: openssl rand -base64 32
  #    - meiliMasterKey: openssl rand -base64 32
  # 2. Configure nextauthUrl to match your public URL
  # 3. After first user registration, set disableRegistration = true
  #
  # The service runs three containers:
  # - linkwarden: Main application (port configured via `port` option)
  # - linkwarden-postgres: PostgreSQL database
  # - linkwarden-meilisearch: Full-text search engine
  #
  # All containers communicate via a dedicated Podman network.

  flake.modules.nixos."services/containers/linkwarden" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      cfg = config.services.linkwarden-container;
    in
    {
      options.services.linkwarden-container = {
        enable = lib.mkEnableOption "Linkwarden bookmark manager";

        port = lib.mkOption {
          type = lib.types.port;
          default = 3000;
          description = "Port for Linkwarden web interface";
        };

        imageTag = lib.mkOption {
          type = lib.types.str;
          default = "latest";
          description = "Linkwarden container image tag";
        };

        dataDir = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/linkwarden";
          description = "Base directory for Linkwarden data";
        };

        postgresPassword = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "PostgreSQL password (leave null to use SOPS template via envFile)";
        };

        nextauthSecret = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "NextAuth secret (leave null to use SOPS template via envFile)";
        };

        meiliMasterKey = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Meilisearch master key (leave null to use SOPS template via envFile)";
        };

        envFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "/run/secrets/rendered/linkwarden-env";
          description = "Path to environment file containing secrets (POSTGRES_PASSWORD, NEXTAUTH_SECRET, MEILI_MASTER_KEY)";
        };

        nextauthUrl = lib.mkOption {
          type = lib.types.str;
          example = "https://linkwarden.example.com";
          description = "Public URL where Linkwarden will be accessible";
        };

        disableRegistration = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Disable new user registration";
        };

        paginationTakeCount = lib.mkOption {
          type = lib.types.int;
          default = 50;
          description = "Number of links to fetch per page";
        };

        autoscrollTimeout = lib.mkOption {
          type = lib.types.int;
          default = 30;
          description = "Timeout for archiving websites (in seconds)";
        };

        cpus = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "2.0";
          example = "2.0";
          description = "Number of CPUs to allocate to Linkwarden container";
        };

        memory = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "2g";
          example = "2g";
          description = "Memory limit for Linkwarden container";
        };

        memoryReservation = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "1g";
          example = "1g";
          description = "Memory soft limit for Linkwarden container";
        };

        shmSize = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "256m";
          example = "256m";
          description = "Shared memory size (important for PDF/screenshot generation)";
        };

        postgres = {
          cpus = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = "1.0";
            description = "Number of CPUs for PostgreSQL";
          };

          memory = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = "1g";
            description = "Memory limit for PostgreSQL";
          };
        };

        meilisearch = {
          cpus = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = "1.0";
            description = "Number of CPUs for Meilisearch";
          };

          memory = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = "512m";
            description = "Memory limit for Meilisearch";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.envFile != null || cfg.postgresPassword != null;
            message = "linkwarden-container: Either envFile or postgresPassword must be set";
          }
        ];

        services.containerPorts = lib.mkAfter [
          {
            service = "linkwarden-container";
            tcpPorts = [ cfg.port ];
          }
        ];

        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0755 root root -"
          "d ${cfg.dataDir}/data 0755 root root -"
          "d ${cfg.dataDir}/pgdata 0755 root root -"
          "d ${cfg.dataDir}/meili_data 0755 root root -"
        ];

        # PostgreSQL container
        environment.etc."containers/systemd/linkwarden-postgres.container".text = ''
          [Unit]
          Description=Linkwarden PostgreSQL Database
          After=network-online.target linkwarden-network.service
          Wants=network-online.target
          Requires=linkwarden-network.service

          [Container]
          ContainerName=linkwarden-postgres
          Image=docker.io/library/postgres:16-alpine
          Network=linkwarden.network
          ${lib.optionalString (cfg.envFile != null) "EnvironmentFile=${cfg.envFile}"}
          ${lib.optionalString (
            cfg.postgresPassword != null
          ) "Environment=POSTGRES_PASSWORD=${cfg.postgresPassword}"}
          Environment=POSTGRES_DB=postgres
          Environment=POSTGRES_USER=postgres
          Volume=${cfg.dataDir}/pgdata:/var/lib/postgresql/data
          ${lib.optionalString (cfg.postgres.cpus != null) "PodmanArgs=--cpus=${cfg.postgres.cpus}"}
          ${lib.optionalString (cfg.postgres.memory != null) "PodmanArgs=--memory=${cfg.postgres.memory}"}
          LogDriver=journald
          LogOpt=tag=linkwarden-postgres

          [Service]
          Restart=always
          RestartSec=10
          TimeoutStartSec=60

          [Install]
          WantedBy=multi-user.target
        '';

        # Meilisearch container
        environment.etc."containers/systemd/linkwarden-meilisearch.container".text = ''
          [Unit]
          Description=Linkwarden Meilisearch
          After=network-online.target linkwarden-network.service
          Wants=network-online.target
          Requires=linkwarden-network.service

          [Container]
          ContainerName=linkwarden-meilisearch
          Image=docker.io/getmeili/meilisearch:v1.12.8
          Network=linkwarden.network
          ${lib.optionalString (cfg.envFile != null) "EnvironmentFile=${cfg.envFile}"}
          ${lib.optionalString (
            cfg.meiliMasterKey != null
          ) "Environment=MEILI_MASTER_KEY=${cfg.meiliMasterKey}"}
          Volume=${cfg.dataDir}/meili_data:/meili_data
          ${lib.optionalString (cfg.meilisearch.cpus != null) "PodmanArgs=--cpus=${cfg.meilisearch.cpus}"}
          ${lib.optionalString (
            cfg.meilisearch.memory != null
          ) "PodmanArgs=--memory=${cfg.meilisearch.memory}"}
          LogDriver=journald
          LogOpt=tag=linkwarden-meilisearch

          [Service]
          Restart=always
          RestartSec=10
          TimeoutStartSec=60

          [Install]
          WantedBy=multi-user.target
        '';

        # Linkwarden main container
        environment.etc."containers/systemd/linkwarden.container".text = ''
          [Unit]
          Description=Linkwarden Bookmark Manager
          After=network-online.target linkwarden-network.service linkwarden-postgres.service linkwarden-meilisearch.service
          Wants=network-online.target
          Requires=linkwarden-network.service linkwarden-postgres.service linkwarden-meilisearch.service

          [Container]
          ContainerName=linkwarden
          Image=ghcr.io/linkwarden/linkwarden:${cfg.imageTag}
          Network=linkwarden.network
          PublishPort=${toString cfg.port}:3000
          Volume=${cfg.dataDir}/data:/data/data
          ${lib.optionalString (cfg.envFile != null) "EnvironmentFile=${cfg.envFile}"}
          Environment=DATABASE_URL=postgresql://postgres:$POSTGRES_PASSWORD@linkwarden-postgres:5432/postgres
          ${lib.optionalString (
            cfg.nextauthSecret != null
          ) "Environment=NEXTAUTH_SECRET=${cfg.nextauthSecret}"}
          Environment=NEXTAUTH_URL=${cfg.nextauthUrl}
          Environment=MEILI_ADDR=http://linkwarden-meilisearch:7700
          ${lib.optionalString (
            cfg.envFile == null && cfg.meiliMasterKey != null
          ) "Environment=MEILI_MASTER_KEY=${cfg.meiliMasterKey}"}
          Environment=NEXT_PUBLIC_DISABLE_REGISTRATION=${if cfg.disableRegistration then "true" else "false"}
          Environment=PAGINATION_TAKE_COUNT=${toString cfg.paginationTakeCount}
          Environment=AUTOSCROLL_TIMEOUT=${toString cfg.autoscrollTimeout}
          Environment=STORAGE_FOLDER=/data/data
          ${lib.optionalString (cfg.cpus != null) "PodmanArgs=--cpus=${cfg.cpus}"}
          ${lib.optionalString (cfg.memory != null) "PodmanArgs=--memory=${cfg.memory}"}
          ${lib.optionalString (
            cfg.memoryReservation != null
          ) "PodmanArgs=--memory-reservation=${cfg.memoryReservation}"}
          ${lib.optionalString (cfg.shmSize != null) "PodmanArgs=--shm-size=${cfg.shmSize}"}
          LogDriver=journald
          LogOpt=tag=linkwarden

          [Service]
          Restart=always
          RestartSec=10
          TimeoutStartSec=120

          [Install]
          WantedBy=multi-user.target
        '';

        # Podman network definition
        environment.etc."containers/systemd/linkwarden.network".text = ''
          [Network]
        '';

        networking.firewall.allowedTCPPorts = [ cfg.port ];
      };
    };
}
