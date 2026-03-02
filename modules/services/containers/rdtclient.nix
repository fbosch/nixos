_: {
  flake.modules.nixos."services/containers/rdtclient" =
    { config
    , lib
    , ...
    }:
    let
      cfg = config.services.rdtclient;
    in
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
          description = "Host path for completed downloads";
        };

        tempDownloadPath = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/rdtclient/temp";
          description = "Host path for temporary/in-progress downloads";
        };

        dataPath = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/rdtclient/data";
          description = "Host path for database and config files";
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

        cpus = lib.mkOption {
          type = lib.types.str;
          default = "1.0";
          example = "1.0";
          description = "CPU limit as a fractional number of CPUs (passed via PodmanArgs --cpus)";
        };

        memory = lib.mkOption {
          type = lib.types.str;
          default = "2g";
          description = "Memory limit for the container";
        };
      };

      config = {
        services.containerPorts = lib.mkAfter [
          {
            service = "rdtclient";
            tcpPorts = [ cfg.port ];
          }
        ];

        systemd.tmpfiles.rules = [
          "d ${cfg.dataPath} 0755 ${toString cfg.userId} ${toString cfg.groupId} -"
        ];

        environment.etc."containers/systemd/rdtclient.container".text = ''
          [Unit]
          After=network-online.target
          Wants=network-online.target
          WantsMountsFor=${cfg.downloadPath}
          WantsMountsFor=${cfg.tempDownloadPath}

          [Container]
          ContainerName=rdtclient
          Image=docker.io/rogerfar/rdtclient:2.0.125
          PublishPort=${cfg.listenAddress}:${toString cfg.port}:6500/tcp
          Volume=${cfg.dataPath}:/data/db
          PodmanArgs=--mount type=bind,src=${cfg.tempDownloadPath},dst=/data/temp
          PodmanArgs=--mount type=bind,src=${cfg.downloadPath},dst=/data/downloads
          Environment=PGID=${toString cfg.groupId}
          Environment=PUID=${toString cfg.userId}
          Environment=TZ=${cfg.timezone}
          Memory=${cfg.memory}
          PidsLimit=500
          Ulimit=nofile=2048:4096
          PodmanArgs=--cpus=${cfg.cpus}
          LogDriver=journald
          LogOpt=tag=rdtclient

          [Service]
          Restart=always
          RestartSec=10
          TimeoutStartSec=infinity
          TimeoutStopSec=30

          [Install]
          WantedBy=multi-user.target
        '';

        networking.firewall.allowedTCPPorts = [ cfg.port ];
      };
    };
}
