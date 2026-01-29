_: {
  flake.modules.nixos."services/komodo" =
    { config
    , lib
    , pkgs
    , ...
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
      ]
        null
        config;
      useAdminBootstrap = cfg.core.initAdminUsername != null && effectiveAdminPasswordFile != null;
      composeFilePath = "/etc/komodo/compose.yaml";
      composeEnvPath = "/etc/komodo/compose.env";
      composeYamlText =
        let
          baseLines = [
            "version: \"3.8\""
            "services:"
            "  mongo:"
            "    image: mongo"
            "    command: --quiet --wiredTigerCacheSizeGB 0.25"
            "    restart: unless-stopped"
            "    volumes:"
            "      - komodo-mongo-data:/data/db"
            "      - komodo-mongo-config:/data/configdb"
            "    environment:"
            "      MONGO_INITDB_ROOT_USERNAME: ${"$"}{KOMODO_DB_USERNAME}"
            "      MONGO_INITDB_ROOT_PASSWORD: ${"$"}{KOMODO_DB_PASSWORD}"
            ""
            "  core:"
            "    image: ghcr.io/moghtech/komodo-core:${"$"}{COMPOSE_KOMODO_IMAGE_TAG:-latest}"
            "    restart: unless-stopped"
            "    depends_on:"
            "      - mongo"
            "    ports:"
            "      - \"${toString cfg.core.port}:9120\""
            "    env_file:"
            "      - ${composeEnvPath}"
            "    environment:"
            "      KOMODO_DATABASE_ADDRESS: mongo:27017"
            "      KOMODO_DATABASE_USERNAME: ${"$"}{KOMODO_DB_USERNAME}"
            "      KOMODO_DATABASE_PASSWORD: ${"$"}{KOMODO_DB_PASSWORD}"
            "    volumes:"
            "      - /var/lib/komodo/backups:/backups"
          ];
          passkeyLine =
            if effectivePasskeyFile != null then
              [
                "      - ${effectivePasskeyFile}:${effectivePasskeyFile}:ro"
              ]
            else
              [ ];
          tailLines = [
            "volumes:"
            "  komodo-mongo-data:"
            "  komodo-mongo-config:"
          ];
        in
        lib.concatStringsSep "\n" (baseLines ++ passkeyLine ++ tailLines) + "\n";
      composeEnvTemplateText =
        let
          lines = builtins.filter (line: line != null) [
            "COMPOSE_KOMODO_IMAGE_TAG=${cfg.core.imageTag}"
            "KOMODO_DB_USERNAME=${config.sops.placeholder.komodo-db-username}"
            "KOMODO_DB_PASSWORD=${config.sops.placeholder.komodo-db-password}"
            "KOMODO_HOST=${cfg.core.host}"
            "KOMODO_TITLE=Komodo"
            "KOMODO_LOCAL_AUTH=true"
            "KOMODO_DISABLE_USER_REGISTRATION=${if cfg.core.allowSignups then "false" else "true"}"
            (if useAdminBootstrap then "KOMODO_INIT_ADMIN_USERNAME=${cfg.core.initAdminUsername}" else null)
            (
              if useAdminBootstrap then "KOMODO_INIT_ADMIN_PASSWORD_FILE=${effectiveAdminPasswordFile}" else null
            )
            (if usePasskey then "KOMODO_PASSKEY_FILE=${effectivePasskeyFile}" else null)
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
        services.komodo-periphery = {
          enable = lib.mkDefault true;
          ssl.enable = false;
          bindIp = "0.0.0.0";
        };

        users.groups.docker = { };
        users.users.komodo-periphery.extraGroups = [ "podman" ];

        services.komodo-periphery.environment = lib.mkMerge [
          (lib.mkIf usePasskey {
            PERIPHERY_PASSKEYS_FILE = effectivePasskeyFile;
          })
          {
            DOCKER_HOST = "unix:///run/podman/podman.sock";
          }
        ];

        # Disable Docker since komodo-periphery enables it by default
        # We use Podman with docker-compat instead (from virtualization/podman.nix)
        virtualisation.docker.enable = lib.mkForce false;

        # Komodo Core via podman-compose
        environment.etc."komodo/compose.yaml" = lib.mkIf cfg.core.enable {
          text = composeYamlText;
        };

        # Link the SOPS-rendered env file to /etc/komodo/compose.env
        environment.etc."komodo/compose.env" = lib.mkIf cfg.core.enable {
          source = config.sops.templates."komodo-compose-env".path;
          mode = "0400";
        };

        systemd = {
          services = {
            komodo-periphery.serviceConfig.SupplementaryGroups = [ "podman" ];

            komodo-core = lib.mkIf cfg.core.enable {
              description = "Komodo Core - Build and Deployment Web UI";
              wantedBy = [ "multi-user.target" ];
              after = [
                "network-online.target"
                "podman.service"
              ];
              wants = [ "network-online.target" ];
              requires = [ "podman.service" ];

              path = [
                pkgs.podman
                pkgs.podman-compose
              ];

              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };

              script = ''
                ${pkgs.podman-compose}/bin/podman-compose -p komodo \
                  -f ${composeFilePath} \
                  --env-file ${composeEnvPath} \
                  up -d
              '';

              preStop = ''
                ${pkgs.podman-compose}/bin/podman-compose -p komodo \
                  -f ${composeFilePath} \
                  --env-file ${composeEnvPath} \
                  down
              '';
            };
          };

          tmpfiles.rules = lib.mkIf cfg.core.enable [
            "d /var/lib/komodo 0750 root root -"
            "d /var/lib/komodo/backups 0750 root root -"
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
              owner = "komodo-periphery";
              group = "komodo-periphery";
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
