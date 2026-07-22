_: {
  flake.modules.nixos."services/containers/termix" =
    { config
    , lib
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
        services.startupPolicy.applications.termix = {
          tier = lib.mkDefault "background";
          units = [
            {
              name = "termix.service";
              provider = "quadlet";
            }
          ];
        };

        services.exposedPorts = lib.mkAfter [
          {
            service = "termix-container";
            tcpPorts = [ config.services.termix-container.port ];
          }
        ];

        environment.etc."containers/systemd/termix.container".text = ''
          [Unit]
          After=network-online.target
          Wants=network-online.target

          [Container]
          ContainerName=termix
          Image=ghcr.io/lukegus/termix:release-2.0.0
          PublishPort=${toString config.services.termix-container.port}:8080
          Volume=termix-data.volume:/app/data
          Environment=PORT=8080
          Memory=1g
          PidsLimit=500
          Ulimit=nofile=2048:4096
          LogDriver=journald
          LogOpt=tag=termix

          [Service]
          RestrictAddressFamilies=~AF_ALG
          SystemCallArchitectures=native
          CPUQuota=400%
          Restart=always
          RestartSec=10
          TimeoutStartSec=300

          [Install]
            WantedBy=${
              lib.attrByPath [
                "services"
                "startupPolicy"
                "quadletTargets"
                "termix.service"
              ] "multi-user.target" config
            }
        '';

        environment.etc."containers/systemd/termix-data.volume".text = ''
          [Volume]
          VolumeName=termix-data
        '';

        # Open firewall for Termix web interface
        networking.firewall.allowedTCPPorts = [ config.services.termix-container.port ];
      };
    };
}
