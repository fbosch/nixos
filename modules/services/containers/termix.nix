_: {
  flake.modules.nixos."services/containers/termix" =
    { config
    , lib
    , pkgs
    , ...
    }:
    {
      options.services.termix-container = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 7310;
          description = "Port for Termix web interface";
        };
      };

      config = {
        services.containerPorts = lib.mkAfter [
          {
            service = "termix-container";
            tcpPorts = [ config.services.termix-container.port ];
          }
        ];

        # Create systemd service for Termix container
        systemd.services.termix-container = {
          description = "Termix SSH Terminal and Server Management Platform";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
            "podman.service"
          ];
          wants = [ "network-online.target" ];
          requires = [ "podman.service" ];

          serviceConfig = {
            Type = "simple";
            Restart = "always";
            RestartSec = "10";
            TimeoutStartSec = "300";
          };

          script = ''
            # Ensure the volume exists
            ${pkgs.podman}/bin/podman volume create termix-data || true

            # Remove existing container if it exists
            ${pkgs.podman}/bin/podman rm -f termix || true

            # Run the container with performance optimizations
            ${pkgs.podman}/bin/podman run \
              --name termix \
              --rm \
              -p ${toString config.services.termix-container.port}:8080 \
              -v termix-data:/app/data \
              -e PORT=8080 \
              --memory=1g \
              --cpus=4 \
              --pids-limit=500 \
              --ulimit nofile=2048:4096 \
              --log-driver=journald \
              --log-opt=tag="termix" \
              ghcr.io/lukegus/termix:latest
          '';

          preStop = ''
            ${pkgs.podman}/bin/podman stop -t 10 termix || true
          '';
        };

        # Open firewall for Termix web interface
        networking.firewall.allowedTCPPorts = [ config.services.termix-container.port ];
      };
    };
}
