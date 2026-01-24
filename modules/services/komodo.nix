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
        else if config ? sops then
          config.sops.secrets.komodo-passkey.path
        else
          null;
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

          imageTag = lib.mkOption {
            type = lib.types.str;
            default = "latest";
            description = "Komodo Core Docker image tag";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        # Enable Komodo Periphery service
        services.komodo-periphery = {
          enable = true;
          environment = lib.mkIf (effectivePasskeyFile != null) {
            PERIPHERY_PASSKEYS_FILE = effectivePasskeyFile;
          };
        };

        # Disable Docker since komodo-periphery enables it by default
        # We use Podman with docker-compat instead (from virtualization/podman.nix)
        virtualisation.docker.enable = lib.mkForce false;

        # Add Komodo CLI tools
        environment.systemPackages = with pkgs; [ komodo ];

        # Komodo Core systemd service
        systemd.services.komodo-core = lib.mkIf cfg.core.enable {
          description = "Komodo Core - Build and Deployment Web UI";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
            "podman.service"
            "komodo-mongo.service"
          ];
          requires = [
            "podman.service"
            "komodo-mongo.service"
          ];

          serviceConfig = {
            Type = "simple";
            Restart = "always";
            RestartSec = "10";
            TimeoutStartSec = "300";
          };

          preStart = ''
            # Create komodo network if it doesn't exist
            ${pkgs.podman}/bin/podman network exists komodo-net || \
              ${pkgs.podman}/bin/podman network create komodo-net
          '';

          script = ''
            # Remove existing container if it exists
            ${pkgs.podman}/bin/podman rm -f komodo-core || true

            # Run Komodo Core container
            ${pkgs.podman}/bin/podman run \
              --name komodo-core \
              --rm \
              --label komodo.skip= \
              --network komodo-net \
              -p ${toString cfg.core.port}:9120 \
              -v /var/lib/komodo/backups:/backups \
              -e KOMODO_DATABASE_ADDRESS=komodo-mongo:27017 \
              ${lib.optionalString (effectivePasskeyFile != null) ''
                -e KOMODO_PASSKEY_FILE=${effectivePasskeyFile} \
              ''}
              -e KOMODO_HOST=http://localhost:${toString cfg.core.port} \
              -e KOMODO_TITLE=Komodo \
              -e KOMODO_FIRST_SERVER=https://komodo-periphery:8120 \
              -e KOMODO_FIRST_SERVER_NAME=Local \
              -e KOMODO_LOCAL_AUTH=true \
              -e TZ=Etc/UTC \
              ghcr.io/moghtech/komodo-core:${cfg.core.imageTag}
          '';

          preStop = ''
            ${pkgs.podman}/bin/podman stop -t 10 komodo-core || true
          '';
        };

        # MongoDB service for Komodo
        systemd.services.komodo-mongo = lib.mkIf cfg.core.enable {
          description = "MongoDB for Komodo";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
            "podman.service"
          ];
          requires = [ "podman.service" ];

          serviceConfig = {
            Type = "simple";
            Restart = "always";
            RestartSec = "10";
            TimeoutStartSec = "300";
          };

          preStart = ''
            # Ensure volumes exist
            ${pkgs.podman}/bin/podman volume create komodo-mongo-data || true
            ${pkgs.podman}/bin/podman volume create komodo-mongo-config || true

            # Create komodo network if it doesn't exist
            ${pkgs.podman}/bin/podman network exists komodo-net || \
              ${pkgs.podman}/bin/podman network create komodo-net
          '';

          script = ''
            # Remove existing container if it exists
            ${pkgs.podman}/bin/podman rm -f komodo-mongo || true

            # Run MongoDB container
            ${pkgs.podman}/bin/podman run \
              --name komodo-mongo \
              --rm \
              --label komodo.skip= \
              --network komodo-net \
              -v komodo-mongo-data:/data/db \
              -v komodo-mongo-config:/data/configdb \
              docker.io/library/mongo:latest \
              --quiet --wiredTigerCacheSizeGB 0.25
          '';

          preStop = ''
            ${pkgs.podman}/bin/podman stop -t 10 komodo-mongo || true
          '';
        };

        # Ensure backup directory exists
        systemd.tmpfiles.rules = lib.mkIf cfg.core.enable [
          "d /var/lib/komodo 0750 root root -"
          "d /var/lib/komodo/backups 0750 root root -"
        ];

        # Open firewall for Komodo Core web interface
        networking.firewall.allowedTCPPorts = lib.mkIf cfg.core.enable [ cfg.core.port ];

        # Wire passkey through sops if available
        sops.secrets.komodo-passkey = lib.mkIf (config ? sops && cfg.passkeyFile == null) {
          mode = "0400";
        };
      };
    };
}
