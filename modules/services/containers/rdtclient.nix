_: {
  flake.modules.nixos."services/containers/rdtclient" =
    { config
    , lib
    , ...
    }:
    {
      options.services.rdtclient = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 6500;
          description = "Port for RDT-Client web interface";
        };

        downloadPath = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/rdtclient/downloads";
          description = "Host path for downloads";
        };

        userId = lib.mkOption {
          type = lib.types.int;
          default = 1000;
          description = "User ID for container process";
        };

        groupId = lib.mkOption {
          type = lib.types.int;
          default = 1000;
          description = "Group ID for container process";
        };

        timezone = lib.mkOption {
          type = lib.types.str;
          default = "UTC";
          description = "Timezone for RDT-Client";
        };

        listenAddress = lib.mkOption {
          type = lib.types.str;
          default = "0.0.0.0";
          description = "Address to bind RDT-Client port on";
        };
      };

      config = {
        services.containerPorts = lib.mkAfter [
          {
            service = "rdtclient";
            tcpPorts = [ config.services.rdtclient.port ];
          }
        ];

        environment.etc = {
          "containers/systemd/rdtclient.container".text = ''
            [Unit]
            Description=RDT-Client - Real-Debrid torrent client
            After=network-online.target
            Wants=network-online.target

            [Container]
            ContainerName=rdtclient
            Image=docker.io/rogerfar/rdtclient:latest
            PublishPort=${config.services.rdtclient.listenAddress}:${toString config.services.rdtclient.port}:6500/tcp
            Volume=rdtclient-data.volume:/data/db
            Volume=${lib.escapeShellArg config.services.rdtclient.downloadPath}:/data/downloads
            Environment=PUID=${toString config.services.rdtclient.userId}
            Environment=PGID=${toString config.services.rdtclient.groupId}
            Environment=TZ=${lib.escapeShellArg config.services.rdtclient.timezone}
            Memory=512m
            PidsLimit=500
            Ulimit=nofile=2048:4096
            HealthCmd=curl -f http://localhost:6500/ || exit 1
            HealthInterval=30s
            HealthTimeout=10s
            HealthStartPeriod=60s
            HealthRetries=3
            LogDriver=journald
            LogOpt=tag=rdtclient

            [Service]
            Restart=always
            RestartSec=10
            CPUQuota=100%
            TimeoutStartSec=300

            [Install]
            WantedBy=multi-user.target
          '';

          "containers/systemd/rdtclient-data.volume".text = ''
            [Volume]
            VolumeName=rdtclient-data
          '';
        };

        networking.firewall.allowedTCPPorts = [ config.services.rdtclient.port ];
      };
    };
}
