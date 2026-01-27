_:
{
  flake.modules.nixos."services/containers/<SERVICE-NAME>" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      cfg = config.services.<SERVICE-NAME>-container;
    in
    {
      options.services.<SERVICE-NAME>-container = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable <SERVICE-NAME> container service";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8080;
          description = "Port for <SERVICE-NAME> web interface";
        };

        image = lib.mkOption {
          type = lib.types.str;
          default = "docker.io/<IMAGE>:<TAG>";
          description = "Container image to use";
        };
      };

      config = lib.mkIf cfg.enable {
        # Create systemd service for container
        systemd.services.<SERVICE-NAME>-container = {
          description = "<SERVICE-NAME> Container Service";
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
            ${pkgs.podman}/bin/podman volume create <SERVICE-NAME>-data || true

            # Remove existing container if it exists
            ${pkgs.podman}/bin/podman rm -f <SERVICE-NAME> || true

            # Run the container
            ${pkgs.podman}/bin/podman run \
              --name <SERVICE-NAME> \
              --rm \
              -p ${toString cfg.port}:8080 \
              -v <SERVICE-NAME>-data:/data \
              ${cfg.image}
          '';

          preStop = ''
            ${pkgs.podman}/bin/podman stop -t 10 <SERVICE-NAME> || true
          '';
        };

        # Open firewall for web interface
        networking.firewall.allowedTCPPorts = [ cfg.port ];
      };
    };
}
