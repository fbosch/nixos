{ config, ... }:
{
  flake.modules.nixos."services/SERVICE_NAME" =
    { config
    , lib
    , pkgs
    , ...
    }:
    {
      options.services.SERVICE_NAME = {
        enable = lib.mkEnableOption "SERVICE_DESCRIPTION";

        port = lib.mkOption {
          type = lib.types.port;
          default = DEFAULT_PORT;
          description = "Port for SERVICE_NAME web interface";
        };
      };

      config = lib.mkIf config.services.SERVICE_NAME.enable {
        # Create systemd service for container
        systemd.services.SERVICE_NAME = {
          description = "SERVICE_DESCRIPTION";
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

          script = ''
            # Ensure the volume exists
            ${pkgs.podman}/bin/podman volume create SERVICE_NAME-data || true

            # Remove existing container if it exists
            ${pkgs.podman}/bin/podman rm -f SERVICE_NAME || true

            # Run the container
            ${pkgs.podman}/bin/podman run \
              --name SERVICE_NAME \
              --rm \
              -p ${toString config.services.SERVICE_NAME.port}:CONTAINER_PORT \
              -v SERVICE_NAME-data:/CONTAINER_DATA_PATH \
              CONTAINER_IMAGE:TAG
          '';

          preStop = ''
            ${pkgs.podman}/bin/podman stop -t 10 SERVICE_NAME || true
          '';
        };

        # Open firewall for web interface
        networking.firewall.allowedTCPPorts = [ config.services.SERVICE_NAME.port ];
      };
    };
}
