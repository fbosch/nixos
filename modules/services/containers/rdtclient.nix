{ config, ... }:
let
  inherit (config.flake.meta.user) username;
in
{
  flake.modules.nixos."services/containers/rdtclient" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      cfg = config.services.rdtclient;
      account = config.users.users.${username};
      primaryGroupId = config.users.groups.${account.group}.gid;
      userManager = "user@${toString cfg.userId}.service";
      cpuQuota = builtins.fromJSON cfg.cpus * 100;
      systemctl = "${pkgs.systemd}/bin/systemctl";
      userUnit = "rdtclient.service";
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
          description = "Local host path for database and config files";
        };

        userId = lib.mkOption {
          type = lib.types.ints.positive;
          default = 1000;
          description = "Host and container UID of the rootless RDT-Client account";
        };

        groupId = lib.mkOption {
          type = lib.types.int;
          default = 1000;
          description = "Group owning the local application data directory";
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
          description = "CPU limit as a fractional number of CPUs";
        };

        memory = lib.mkOption {
          type = lib.types.str;
          default = "2g";
          description = "Memory limit for the container";
        };
      };

      config = {
        assertions = [
          {
            assertion = account.uid == cfg.userId && primaryGroupId != null;
            message = "rdtclient requires a matching static host UID and a static primary GID for its rootless account.";
          }
          {
            assertion = cpuQuota > 0;
            message = "rdtclient requires a positive CPU limit.";
          }
        ];

        users.users.${username} = {
          uid = lib.mkDefault cfg.userId;
          linger = true;
        };

        services.startupPolicy.applications.rdtclient = {
          tier = lib.mkDefault "background";
          units = [
            {
              name = "rdtclient.service";
              provider = "nixos";
            }
          ];
        };

        services.exposedPorts = lib.mkAfter [
          {
            service = "rdtclient";
            tcpPorts = [ cfg.port ];
          }
        ];

        systemd = {
          tmpfiles.rules = [
            "d ${cfg.dataPath} 0700 ${toString cfg.userId} ${toString cfg.groupId} -"
          ];

          # System mounts and startup tiers cannot be dependencies of a user unit.
          services.rdtclient = {
            description = "RDT-Client rootless Quadlet controller";
            requires = [ userManager ];
            bindsTo = [ userManager ];
            wants = [ "network-online.target" ];
            after = [ userManager "network-online.target" ];
            unitConfig = {
              RequiresMountsFor = [ cfg.dataPath cfg.downloadPath cfg.tempDownloadPath ];
              StartLimitIntervalSec = "1h";
              StartLimitBurst = 3;
            };
            environment.XDG_RUNTIME_DIR = "/run/user/${toString cfg.userId}";
            preStart = ''
              ${systemctl} --user daemon-reload
              ${systemctl} --user stop ${userUnit}

              database=${lib.escapeShellArg "${cfg.dataPath}/rdtclient.db"}
              backup=${lib.escapeShellArg "${cfg.dataPath}/rdtclient.pre-rootless.db"}
              if [[ -f "$database" && ! -e "$backup" ]]; then
                if [[ -s "$database-wal" || -s "$database-journal" ]]; then
                  echo "RDT database journal present; take a consistent SQLite backup before migration" >&2
                  exit 1
                fi
                temporary=$(${pkgs.coreutils}/bin/mktemp "$backup.XXXXXX")
                trap '${pkgs.coreutils}/bin/rm -f -- "$temporary"' EXIT
                ${pkgs.coreutils}/bin/cat -- "$database" > "$temporary"
                ${pkgs.coreutils}/bin/sync -- "$temporary"
                ${pkgs.coreutils}/bin/ln -T -- "$temporary" "$backup"
                ${pkgs.coreutils}/bin/sync -- ${lib.escapeShellArg cfg.dataPath}
                ${pkgs.coreutils}/bin/rm -- "$temporary"
                trap - EXIT
              fi
              ${pkgs.coreutils}/bin/touch /run/rdtclient/ready
            '';
            serviceConfig = {
              Type = "exec";
              User = username;
              RuntimeDirectory = "rdtclient";
              RuntimeDirectoryMode = "0700";
              # --wait observes user-unit failures; the second start waits for readiness.
              ExecStart = "${systemctl} --user --wait start ${userUnit}";
              ExecStartPost = "${systemctl} --user start ${userUnit}";
              ExecStop = "${systemctl} --user stop ${userUnit}";
              # Also stop a user container whose startup failed before the controller was ready.
              ExecStopPost = "-${systemctl} --user stop ${userUnit}";
              Restart = "always";
              RestartSec = 60;
              TimeoutStartSec = 900;
              TimeoutStopSec = 90;
            };
          };
        };

        environment.etc."containers/systemd/users/${toString cfg.userId}/rdtclient.container".text = ''
          [Container]
          ContainerName=rdtclient
          Image=docker.io/rogerfar/rdtclient:2.0.142
          UserNS=keep-id
          User=${toString cfg.userId}:${toString primaryGroupId}
          GroupAdd=keep-groups
          PodmanArgs=--runtime=${pkgs.crun}/bin/crun
          # The image's s6 launcher resets groups and can recursively chown /data.
          Entrypoint=dotnet
          Exec=RdtClient.Web.dll
          WorkingDir=/app
          Environment=SKIP_CHOWN=true
          Environment=HOME=/data/db
          Environment=XDG_CONFIG_HOME=/data/db/.config
          Environment=TZ=${cfg.timezone}
          PublishPort=${cfg.listenAddress}:${toString cfg.port}:6500/tcp
          Volume=${cfg.dataPath}:/data/db
          Mount=type=bind,src=${cfg.tempDownloadPath},dst=/data/temp
          Mount=type=bind,src=${cfg.downloadPath},dst=/data/downloads
          ReadOnly=true
          NoNewPrivileges=true
          DropCapability=all
          Memory=${cfg.memory}
          PidsLimit=500
          Ulimit=nofile=2048:4096
          HealthCmd=curl --fail --silent --output /dev/null http://127.0.0.1:6500/
          HealthInterval=30s
          HealthTimeout=10s
          HealthStartPeriod=30s
          HealthRetries=3
          HealthOnFailure=kill
          Notify=healthy
          StopTimeout=60
          LogDriver=journald
          LogOpt=tag=rdtclient

          [Service]
          # Only the mount-ordered system controller may release this startup guard.
          ExecStartPre=${pkgs.coreutils}/bin/test -f /run/rdtclient/ready
          RestrictAddressFamilies=~AF_ALG
          SystemCallArchitectures=native
          CPUQuota=${toString cpuQuota}%
          Restart=no
          TimeoutStartSec=900
          TimeoutStopSec=75
        '';

        networking.firewall.allowedTCPPorts = [ cfg.port ];
      };
    };
}
