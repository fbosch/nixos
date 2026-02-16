_: {
  flake.modules.nixos."services/containers/speedtest-tracker" =
    { config
    , lib
    , ...
    }:
    let
      cfg = config.services.speedtest-tracker;
    in
    {
      options.services.speedtest-tracker = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Speedtest Tracker container";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8085;
          description = "Port for Speedtest Tracker web interface";
        };

        appUrl = lib.mkOption {
          type = lib.types.str;
          default = "http://localhost:8085";
          description = "Public URL for Speedtest Tracker (APP_URL)";
        };

        puid = lib.mkOption {
          type = lib.types.int;
          default = 1000;
          description = "User ID for container filesystem permissions";
        };

        pgid = lib.mkOption {
          type = lib.types.int;
          default = 1000;
          description = "Group ID for container filesystem permissions";
        };

        imageTag = lib.mkOption {
          type = lib.types.str;
          default = "latest";
          description = "Speedtest Tracker Docker image tag";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.etc = {
          "containers/systemd/speedtest-tracker.container".text = ''
            [Unit]
            After=network-online.target
            Wants=network-online.target

            [Container]
            ContainerName=speedtest-tracker
            Image=lscr.io/linuxserver/speedtest-tracker:${cfg.imageTag}
            PublishPort=${toString cfg.port}:80
            Environment=PUID=${toString cfg.puid}
            Environment=PGID=${toString cfg.pgid}
            Environment=APP_URL=${lib.escapeShellArg cfg.appUrl}
            Environment=DB_CONNECTION=sqlite
            EnvironmentFile=${config.sops.templates."speedtest-tracker-env".path}
            Volume=speedtest-tracker-data.volume:/config
            Memory=512m
            PidsLimit=500
            Ulimit=nofile=2048:4096
            HealthCmd=curl -fsS http://localhost:80 || exit 1
            HealthInterval=30s
            HealthTimeout=10s
            HealthStartPeriod=60s
            HealthRetries=3
            LogDriver=journald
            LogOpt=tag=speedtest-tracker

            [Service]
            Restart=always
            RestartSec=10
            CPUQuota=100%
            TimeoutStartSec=300

            [Install]
            WantedBy=multi-user.target
          '';

          "containers/systemd/speedtest-tracker-data.volume".text = ''
            [Volume]
            VolumeName=speedtest-tracker-data
          '';
        };

        systemd.tmpfiles.rules = [
          "d /var/lib/speedtest-tracker 0750 root root -"
        ];

        networking.firewall.allowedTCPPorts = [ cfg.port ];

        # Wire APP_KEY through sops
        sops.secrets.speedtest-tracker-app-key = {
          mode = "0400";
          sopsFile = ../../../secrets/containers.yaml;
        };

        sops.templates."speedtest-tracker-env" = {
          content = ''
            APP_KEY=${config.sops.placeholder.speedtest-tracker-app-key}
          '';
          mode = "0400";
        };
      };
    };
}
