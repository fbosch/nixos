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
      };

      config = {
        services.containerPorts = lib.mkAfter [
          {
            service = "rdtclient";
            tcpPorts = [ config.services.rdtclient.port ];
          }
        ];

        # Create directories for rdtclient volumes
        systemd.services.create-rdtclient-volume = {
          description = "Create rdtclient data directories";
          wantedBy = [ "rdtclient.service" ];
          before = [ "rdtclient.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            mkdir -p ${lib.escapeShellArg config.services.rdtclient.dataPath}
            mkdir -p ${lib.escapeShellArg config.services.rdtclient.tempDownloadPath}
            chown ${toString config.services.rdtclient.userId}:${toString config.services.rdtclient.groupId} ${lib.escapeShellArg config.services.rdtclient.dataPath}
            chown ${toString config.services.rdtclient.userId}:${toString config.services.rdtclient.groupId} ${lib.escapeShellArg config.services.rdtclient.tempDownloadPath}
          '';
        };

        # Traditional systemd service instead of Quadlet
        systemd.services.rdtclient = {
          description = "RDT-Client - Real-Debrid torrent client";
          after = [
            "network-online.target"
            "create-rdtclient-volume.service"
          ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            Type = "simple";
            Restart = "always";
            RestartSec = "10";
            TimeoutStartSec = "infinity";
            TimeoutStopSec = "30";
          };

          script = ''
            exec ${config.virtualisation.podman.package}/bin/podman run \
              --name rdtclient \
              --rm \
              --log-driver journald \
              --log-opt tag=rdtclient \
              --memory 2g \
              --pids-limit 500 \
              --ulimit nofile=2048:4096 \
              -v ${lib.escapeShellArg config.services.rdtclient.dataPath}:/data/db \
              -v ${lib.escapeShellArg config.services.rdtclient.tempDownloadPath}:/data/temp \
              -v ${lib.escapeShellArg config.services.rdtclient.downloadPath}:/data/downloads \
              --publish ${config.services.rdtclient.listenAddress}:${toString config.services.rdtclient.port}:6500/tcp \
              --env PGID=${toString config.services.rdtclient.groupId} \
              --env PUID=${toString config.services.rdtclient.userId} \
              --env TZ=${lib.escapeShellArg config.services.rdtclient.timezone} \
              docker.io/rogerfar/rdtclient:latest
          '';

          preStop = ''
            ${config.virtualisation.podman.package}/bin/podman stop -t 10 rdtclient || true
          '';
        };

        networking.firewall.allowedTCPPorts = [ config.services.rdtclient.port ];
      };
    };
}
