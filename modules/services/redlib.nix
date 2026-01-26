{ config, ... }:
{
  flake.modules.nixos."services/redlib" =
    { config
    , lib
    , pkgs
    , ...
    }:
    {
      options.services.redlib-container = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Redlib - Private front-end for Reddit (containerized)";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8282;
          description = "Port for Redlib web interface";
        };
      };

      config = lib.mkIf config.services.redlib-container.enable {
        # Create systemd service for Redlib container
        systemd.services.redlib-container = {
          description = "Redlib - Private front-end for Reddit (containerized)";
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
            # Remove existing container if it exists
            ${pkgs.podman}/bin/podman rm -f redlib || true

            # Run the container
            ${pkgs.podman}/bin/podman run \
              --name redlib \
              --rm \
              -p ${toString config.services.redlib-container.port}:8080 \
              quay.io/redlib/redlib:latest
          '';

          preStop = ''
            ${pkgs.podman}/bin/podman stop -t 10 redlib || true
          '';
        };

        # Open firewall for Redlib web interface
        networking.firewall.allowedTCPPorts = [ config.services.redlib-container.port ];
      };
    };
}
