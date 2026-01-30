_: {
  flake.modules.nixos."services/containers/redlib" =
    { config
    , lib
    , ...
    }:
    {
      options.services.redlib-container = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 8282;
          description = "Port for Redlib web interface";
        };
      };

      config = {
        services.containerPorts = lib.mkAfter [
          {
            service = "redlib-container";
            tcpPorts = [ config.services.redlib-container.port ];
          }
        ];

        environment.etc."containers/systemd/redlib.container".text = ''
          [Unit]
          After=network-online.target
          Wants=network-online.target

          [Container]
          ContainerName=redlib
          Image=quay.io/redlib/redlib:latest
          PublishPort=${toString config.services.redlib-container.port}:8080
          Memory=512m
          PidsLimit=200
          Ulimit=nofile=1024:2048
          LogDriver=journald
          LogOpt=tag=redlib

          [Service]
          CPUQuota=200%
          Restart=always
          RestartSec=10
          TimeoutStartSec=300

          [Install]
          WantedBy=multi-user.target
        '';

        # Open firewall for Redlib web interface
        networking.firewall.allowedTCPPorts = [ config.services.redlib-container.port ];
      };
    };
}
