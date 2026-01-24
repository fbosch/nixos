{ config, ... }:
{
  flake.modules.nixos."services/komodo" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      cfg = config.services.komodo;
      effectivePasskeyFile =
        if cfg.passkeyFile != null then
          cfg.passkeyFile
        else if config ? sops && config.sops.secrets ? "komodo-passkey" then
          config.sops.secrets.komodo-passkey.path
        else
          null;
      usePasskey = cfg.periphery.requirePasskey && effectivePasskeyFile != null;
      effectiveAdminPasswordFile =
        if cfg.core.initAdminPasswordFile != null then
          cfg.core.initAdminPasswordFile
        else if config ? sops && config.sops.secrets ? "komodo-admin-password" then
          config.sops.secrets.komodo-admin-password.path
        else
          null;
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
      composeEnvText =
        let
          lines = builtins.filter (line: line != null) [
            "COMPOSE_KOMODO_IMAGE_TAG=${cfg.core.imageTag}"
            "KOMODO_DB_USERNAME=admin"
            "KOMODO_DB_PASSWORD=admin"
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
        enable = lib.mkEnableOption "Komodo build and deployment system";

        passkeyFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Path to file containing the Komodo passkey (e.g., from SOPS)";
          example = lib.literalExpression "config.sops.secrets.komodo-passkey.path";
        };

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

          initAdminPasswordFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Path to file containing initial admin password";
            example = lib.literalExpression "config.sops.secrets.komodo-admin-password.path";
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

      config = lib.mkIf cfg.enable {
        # Enable Komodo Periphery service
        services.komodo-periphery = {
          enable = true;
          ssl.enable = false;
          bindIp = "0.0.0.0";
        };

        users.groups.docker = { };
        users.users.komodo-periphery.extraGroups = [ "podman" ];
        systemd.services.komodo-periphery.serviceConfig.SupplementaryGroups = [ "podman" ];
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

        environment.etc."komodo/compose.env" = lib.mkIf (cfg.core.enable && !(config ? sops)) {
          text = composeEnvText;
          mode = "0400";
        };

        system.activationScripts.komodoComposeEnv = lib.mkIf cfg.core.enable ''
          if [ -f /etc/komodo/compose.env ] && [ ! -L /etc/komodo/compose.env ]; then
            rm -f /etc/komodo/compose.env
          fi
          ${lib.optionalString (config ? sops) ''
            if [ -f ${config.sops.templates."komodo-compose-env".path} ]; then
              install -m 0400 ${config.sops.templates."komodo-compose-env".path} /etc/komodo/compose.env
            fi
          ''}
        '';

        systemd.services.komodo-core = lib.mkIf cfg.core.enable {
          description = "Komodo Core - Build and Deployment Web UI";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
            "podman.service"
          ];
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

        systemd.tmpfiles.rules = lib.mkIf cfg.core.enable [
          "d /var/lib/komodo 0750 root root -"
          "d /var/lib/komodo/backups 0750 root root -"
        ];

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.core.enable [
          cfg.core.port
          8120
        ];

        # Wire passkey through sops if available
        sops.secrets.komodo-passkey =
          lib.mkIf (config ? sops && cfg.passkeyFile == null && cfg.periphery.requirePasskey)
            {
              mode = "0440";
              owner = "komodo-periphery";
              group = "komodo-periphery";
            };

        sops.secrets.komodo-db-username = lib.mkIf (config ? sops) {
          mode = "0400";
        };

        sops.secrets.komodo-db-password = lib.mkIf (config ? sops) {
          mode = "0400";
        };

        sops.secrets.komodo-admin-password =
          lib.mkIf
            (config ? sops && cfg.core.initAdminUsername != null && cfg.core.initAdminPasswordFile == null)
            {
              mode = "0400";
            };

        sops.templates."komodo-compose-env" = lib.mkIf (config ? sops && cfg.core.enable) {
          content = composeEnvTemplateText;
          mode = "0400";
        };
      };
    };
}
