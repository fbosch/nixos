{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos."services/termix" =
    { config
    , lib
    , pkgs
    , ...
    }:
    {
      options.services.termix = {
        enable = lib.mkEnableOption "Termix SSH Terminal and Server Management Platform";

        port = lib.mkOption {
          type = lib.types.port;
          default = 8080;
          description = "Port for Termix web interface";
        };
      };

      config = lib.mkIf config.services.termix.enable {
        # Create systemd user service for Termix container (rootless)
        systemd.user.services.termix = {
          description = "Termix SSH Terminal and Server Management Platform";
          wantedBy = [ "default.target" ];
          after = [ "network-online.target" ];

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

            # Run the container
            ${pkgs.podman}/bin/podman run \
              --name termix \
              --rm \
              -p ${toString config.services.termix.port}:8080 \
              -v termix-data:/app/data \
              -e PORT=8080 \
              ghcr.io/lukegus/termix:latest
          '';

          preStop = ''
            ${pkgs.podman}/bin/podman stop -t 10 termix || true
          '';
        };

        # Enable lingering so user services run without login
        users.users.${flakeConfig.flake.meta.user.username}.linger = true;

        # Open firewall for Termix web interface
        networking.firewall.allowedTCPPorts = [ config.services.termix.port ];
      };
    };
}
