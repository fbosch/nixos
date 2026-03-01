_: {
  flake.modules.nixos."services/containers/flaresolverr" =
    { config
    , lib
    , ...
    }:
    let
      cfg = config.services.flaresolverr-container;
    in
    {
      options.services.flaresolverr-container = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 8191;
          description = "Port for FlareSolverr HTTP API";
        };

        listenAddress = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Address to bind FlareSolverr port on";
        };

        logLevel = lib.mkOption {
          type = lib.types.enum [
            "debug"
            "info"
            "warning"
            "error"
          ];
          default = "info";
          description = "FlareSolverr log level";
        };

        imageTag = lib.mkOption {
          type = lib.types.str;
          default = "v3.4.6";
          description = "FlareSolverr Docker image tag";
        };
      };

      config = {
        services.containerPorts = lib.mkAfter [
          {
            service = "flaresolverr-container";
            tcpPorts = [ cfg.port ];
          }
        ];

        environment.etc."containers/systemd/flaresolverr.container".text = ''
          [Unit]
          Description=FlareSolverr - Cloudflare challenge solver proxy
          After=network-online.target
          Wants=network-online.target

          [Container]
          ContainerName=flaresolverr
          Image=ghcr.io/flaresolverr/flaresolverr:${cfg.imageTag}
          PublishPort=${cfg.listenAddress}:${toString cfg.port}:8191
          Environment=LOG_LEVEL=${cfg.logLevel}
          Memory=1g
          PidsLimit=500
          Ulimit=nofile=2048:4096
          LogDriver=journald
          LogOpt=tag=flaresolverr

          [Service]
          Restart=always
          RestartSec=10
          TimeoutStartSec=120

          [Install]
          WantedBy=multi-user.target
        '';

        networking.firewall.allowedTCPPorts = [ cfg.port ];
      };
    };
}
