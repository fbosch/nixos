{ config, ... }:
let
  inherit (config.flake.lib) startupPolicy;
in
{
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

        listenAddresses = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "127.0.0.1" ];
          description = "Host addresses to bind the Termix port on.";
        };
      };

      config = {
        assertions = [
          {
            assertion = config.services.termix-container.listenAddresses != [ ];
            message = "services.termix-container.listenAddresses must not be empty";
          }
        ];

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

        environment.etc."containers/systemd/termix.container".text =
          let
            cfg = config.services.termix-container;
            publishPortBlock = lib.concatStringsSep "\n" (
              map (addr: "PublishPort=${addr}:${toString cfg.port}:8080") cfg.listenAddresses
            );
          in
          ''
              [Unit]
              After=network-online.target
              Wants=network-online.target

              [Container]
              ContainerName=termix
              Image=ghcr.io/lukegus/termix:release-2.0.0
              ${publishPortBlock}
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
              WantedBy=${(startupPolicy.quadlet config "termix.service").target}
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
