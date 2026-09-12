{ config, ... }:
let
  inherit (config.flake.lib) sopsFiles sopsHelpers startupPolicy;
in
{
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
      containersFile = sopsFiles.containers;
      meilisearchVersion = lib.removePrefix "v" cfg.meilisearch.imageTag;
      meilisearchBackupBeforeUpgrade = pkgs.writeShellApplication {
        name = "linkwarden-meilisearch-backup-before-upgrade";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.findutils
        ];
        text = ''
          set -euo pipefail

          data_dir=${lib.escapeShellArg cfg.dataDir}
          target_version=${lib.escapeShellArg meilisearchVersion}
          database="$data_dir/meili_data/data.ms"
          version_file="$database/VERSION"

          if [[ ! -f "$version_file" ]]; then
            if [[ -e "$database" ]]; then
              printf 'Meilisearch database exists without a VERSION file at %s.\n' "$database" >&2
              exit 1
            fi
            exit 0
          fi

          current_version="$(tr -d '[:space:]' < "$version_file")"
          if [[ "$current_version" == "$target_version" ]]; then
            exit 0
          fi

          backup_root="$data_dir/meili-backups"
          fingerprint="$(
            cd "$database"
            find . -printf '%P\0%y\0%s\0%T@\0' |
              sort -z |
              sha256sum |
              cut -d ' ' -f 1
          )"
          backup="$backup_root/data.ms-$current_version-before-$target_version-$fingerprint"
          completion_marker="$backup.complete"
          install -d -m 0750 "$backup_root"

          if [[ -e "$backup" && ! -f "$completion_marker" ]]; then
            printf 'Incomplete Meilisearch backup requires inspection: %s.\n' "$backup" >&2
            exit 1
          fi

          if [[ ! -e "$backup" ]]; then
            rm -f -- "$completion_marker"
            temporary="$(mktemp -d "$backup_root/.data.ms-backup.XXXXXX")"
            trap 'rm -rf -- "$temporary"' EXIT
            cp -a --reflink=auto -- "$database" "$temporary/data.ms"

            if [[ ! -f "$temporary/data.ms/VERSION" ]] ||
              [[ "$(tr -d '[:space:]' < "$temporary/data.ms/VERSION")" != "$current_version" ]]; then
              printf 'Temporary Meilisearch backup does not match database version %s.\n' \
                "$current_version" >&2
              exit 1
            fi

            sync -f "$temporary/data.ms"
            mv -- "$temporary/data.ms" "$backup"
            rmdir -- "$temporary"
            trap - EXIT
            sync -f "$backup_root"
            install -m 0400 /dev/null "$completion_marker"
            sync -f "$backup_root"
          fi

          if [[ ! -f "$backup/VERSION" ]] ||
            [[ "$(tr -d '[:space:]' < "$backup/VERSION")" != "$current_version" ]]; then
            printf 'Meilisearch backup at %s does not match database version %s.\n' \
              "$backup" "$current_version" >&2
            exit 1
          fi

          printf 'Prepared Meilisearch %s to %s upgrade; backup: %s\n' \
            "$current_version" "$target_version" "$backup"
        '';
      };
    in
    {
      options.services.linkwarden-container = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 3000;
          description = "Port for Linkwarden web interface";
        };

        imageTag = lib.mkOption {
          type = lib.types.str;
          default = "v2.16.1";
          description = "Linkwarden container image tag";
        };

        dataDir = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/linkwarden";
          description = "Base directory for Linkwarden data";
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
          imageTag = lib.mkOption {
            type = lib.types.strMatching "^v[0-9]+\\.[0-9]+\\.[0-9]+$";
            default = "v1.53.1";
            description = "Meilisearch container image tag";
          };

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

      config = {
        services = {
          startupPolicy.applications.linkwarden = {
            tier = lib.mkDefault "background";
            units =
              map
                (name: {
                  inherit name;
                  provider = "quadlet";
                })
                [
                  "linkwarden-postgres.service"
                  "linkwarden-meilisearch.service"
                  "linkwarden.service"
                ];
          };

          linkwarden-container.envFile = lib.mkDefault (
            lib.attrByPath [ "sops" "templates" "linkwarden-env" "path" ] null config
          );

          exposedPorts = lib.mkAfter [
            {
              service = "linkwarden-container";
              tcpPorts = [ cfg.port ];
            }
          ];
        };

        sops = {
          secrets = sopsHelpers.mkSecretsWithOpts containersFile sopsHelpers.rootOnly [
            "linkwarden-postgres-password"
            "linkwarden-nextauth-secret"
            "linkwarden-meili-master-key"
          ];

          templates."linkwarden-env" = {
            content = ''
              POSTGRES_PASSWORD=${config.sops.placeholder.linkwarden-postgres-password}
              DATABASE_URL=postgresql://postgres:${config.sops.placeholder.linkwarden-postgres-password}@linkwarden-postgres:5432/postgres
              NEXTAUTH_SECRET=${config.sops.placeholder.linkwarden-nextauth-secret}
              MEILI_MASTER_KEY=${config.sops.placeholder.linkwarden-meili-master-key}
              DISABLE_PRESERVATION=true
            '';
            mode = "0400";
          };
        };

        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0755 root root -"
          "d ${cfg.dataDir}/data 0755 root root -"
          "d ${cfg.dataDir}/pgdata 0755 root root -"
          "d ${cfg.dataDir}/meili_data 0755 root root -"
        ];

        environment.etc = {
          # PostgreSQL container
          "containers/systemd/linkwarden-postgres.container".text = ''
            [Unit]
            Description=Linkwarden PostgreSQL Database
            After=network-online.target linkwarden-network.service
            Wants=network-online.target
            Requires=linkwarden-network.service

            [Container]
            ContainerName=linkwarden-postgres
            Image=docker.io/library/postgres:18-alpine
            Network=linkwarden.network
            EnvironmentFile=${cfg.envFile}
            Environment=POSTGRES_DB=postgres
            Environment=POSTGRES_USER=postgres
            Volume=${cfg.dataDir}/pgdata:/var/lib/postgresql/data
            ${lib.optionalString (cfg.postgres.cpus != null) "PodmanArgs=--cpus=${cfg.postgres.cpus}"}
            ${lib.optionalString (cfg.postgres.memory != null) "Memory=${cfg.postgres.memory}"}
            LogDriver=journald
            LogOpt=tag=linkwarden-postgres

            [Service]
            Slice=${(startupPolicy.quadlet config "linkwarden-postgres.service").slice}
            RestrictAddressFamilies=~AF_ALG
            SystemCallArchitectures=native
            Restart=always
            RestartSec=10
            TimeoutStartSec=60

            [Install]
            WantedBy=${(startupPolicy.quadlet config "linkwarden-postgres.service").target}
          '';

          # Meilisearch container
          "containers/systemd/linkwarden-meilisearch.container".text = ''
            [Unit]
            Description=Linkwarden Meilisearch
            After=network-online.target linkwarden-network.service
            Wants=network-online.target
            Requires=linkwarden-network.service

            [Container]
            ContainerName=linkwarden-meilisearch
            Image=docker.io/getmeili/meilisearch:${cfg.meilisearch.imageTag}
            Network=linkwarden.network
            PodmanArgs=--network-alias=meilisearch
            EnvironmentFile=${cfg.envFile}
            Environment=MEILI_UPGRADE_DB=true
            Volume=${cfg.dataDir}/meili_data:/meili_data
            ${lib.optionalString (cfg.meilisearch.cpus != null) "PodmanArgs=--cpus=${cfg.meilisearch.cpus}"}
            ${lib.optionalString (cfg.meilisearch.memory != null) "Memory=${cfg.meilisearch.memory}"}
            LogDriver=journald
            LogOpt=tag=linkwarden-meilisearch

            [Service]
            Slice=${(startupPolicy.quadlet config "linkwarden-meilisearch.service").slice}
            ExecStartPre=${meilisearchBackupBeforeUpgrade}/bin/linkwarden-meilisearch-backup-before-upgrade
            RestrictAddressFamilies=~AF_ALG
            SystemCallArchitectures=native
            Restart=always
            RestartSec=10
            TimeoutStartSec=1h

            [Install]
            WantedBy=${(startupPolicy.quadlet config "linkwarden-meilisearch.service").target}
          '';

          # Linkwarden main container
          "containers/systemd/linkwarden.container".text = ''
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
            EnvironmentFile=${cfg.envFile}
            Environment=NEXTAUTH_URL=${cfg.nextauthUrl}
            Environment=MEILI_ADDR=http://linkwarden-meilisearch:7700
            Environment=NEXT_PUBLIC_DISABLE_REGISTRATION=${if cfg.disableRegistration then "true" else "false"}
            Environment=PAGINATION_TAKE_COUNT=${toString cfg.paginationTakeCount}
            Environment=AUTOSCROLL_TIMEOUT=${toString cfg.autoscrollTimeout}
            Environment=STORAGE_FOLDER=/data/data
            Environment=NODE_OPTIONS=--max-old-space-size=3072
            ${lib.optionalString (cfg.cpus != null) "PodmanArgs=--cpus=${cfg.cpus}"}
            ${lib.optionalString (cfg.memory != null) "Memory=${cfg.memory}"}
            ${lib.optionalString (
              cfg.memoryReservation != null
            ) "PodmanArgs=--memory-reservation=${cfg.memoryReservation}"}
            ${lib.optionalString (cfg.shmSize != null) "ShmSize=${cfg.shmSize}"}
            LogDriver=journald
            LogOpt=tag=linkwarden

            [Service]
            Slice=${(startupPolicy.quadlet config "linkwarden.service").slice}
            RestrictAddressFamilies=~AF_ALG
            SystemCallArchitectures=native
            Restart=always
            RestartSec=10
            TimeoutStartSec=120

            [Install]
            WantedBy=${(startupPolicy.quadlet config "linkwarden.service").target}
          '';

          # Podman network definition
          "containers/systemd/linkwarden.network".text = ''
            [Network]
            NetworkName=linkwarden
          '';
        };

        networking.firewall.allowedTCPPorts = [ cfg.port ];
      };
    };
}
