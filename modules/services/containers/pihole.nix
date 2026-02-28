{ config, ... }:
let
  inherit (config.flake.lib) sopsHelpers;
in
{
  flake.modules.nixos."services/containers/pihole" =
    { config
    , lib
    , ...
    }:
    let
      cfg = config.services.pihole-container;
    in
    {
      options.services.pihole-container = {
        webPort = lib.mkOption {
          type = lib.types.port;
          default = 8081;
          description = "Port for Pi-hole web interface";
        };

        dnsPort = lib.mkOption {
          type = lib.types.port;
          default = 53;
          description = "Port for Pi-hole DNS";
        };

        listenAddress = lib.mkOption {
          type = lib.types.str;
          default = "0.0.0.0";
          description = "Address to bind Pi-hole ports on";
        };

        timezone = lib.mkOption {
          type = lib.types.str;
          default = "UTC";
          description = "Timezone for Pi-hole";
        };

        webPassword = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Web UI password (empty = auto-generate)";
        };

        webPasswordFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Path to env file containing FTLCONF_webserver_api_password";
        };

        dnsListeningMode = lib.mkOption {
          type = lib.types.str;
          default = "ALL";
          description = "FTL DNS listening mode (recommended ALL for bridge networking)";
        };

        dnsUpstreams = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Upstream DNS servers (semicolon-delimited in FTLCONF_dns_upstreams)";
        };

        dnsForwardMax = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = 300;
          description = "dnsmasq --dns-forward-max value; set null to use default";
        };
      };

      config = {
        sops.secrets."pihole-default-password" =
          sopsHelpers.mkSecret ../../../secrets/containers.yaml sopsHelpers.rootOnly;

        services.pihole-container.webPasswordFile = lib.mkDefault (
          lib.attrByPath [ "sops" "templates" "pihole-webpassword" "path" ] null config
        );

        sops.templates."pihole-webpassword" = {
          content = ''
            FTLCONF_webserver_api_password=${config.sops.placeholder.pihole-default-password}
          '';
          mode = "0400";
        };

        services.containerPorts = lib.mkAfter [
          {
            service = "pihole-container";
            tcpPorts = [
              cfg.webPort
              cfg.dnsPort
            ];
            udpPorts = [ cfg.dnsPort ];
          }
        ];

        environment.etc = {
          "containers/systemd/pihole.container".text = ''
            [Unit]
            After=network-online.target
            Wants=network-online.target

            [Container]
            ContainerName=pihole
            Image=pihole/pihole:latest
            PublishPort=${cfg.listenAddress}:${toString cfg.dnsPort}:53/tcp
            PublishPort=${cfg.listenAddress}:${toString cfg.dnsPort}:53/udp
            PublishPort=${cfg.listenAddress}:${toString cfg.webPort}:80/tcp
            Volume=pihole-data.volume:/etc/pihole
            Volume=pihole-dnsmasq.volume:/etc/dnsmasq.d
            Environment=TZ=${lib.escapeShellArg cfg.timezone}
            Environment=FTLCONF_dns_listeningMode=${lib.escapeShellArg cfg.dnsListeningMode}
            ${lib.optionalString (cfg.dnsUpstreams != [ ]) ''
              Environment=FTLCONF_dns_upstreams=${lib.escapeShellArg (lib.concatStringsSep ";" cfg.dnsUpstreams)}
            ''}
            ${lib.optionalString (cfg.dnsForwardMax != null) ''
              Environment=FTL_CMD=${lib.escapeShellArg "no-daemon -- --dns-forward-max ${toString cfg.dnsForwardMax}"}
            ''}
            ${lib.optionalString (cfg.webPasswordFile != null) ''
              EnvironmentFile=${lib.escapeShellArg cfg.webPasswordFile}
            ''}
            ${lib.optionalString (cfg.webPasswordFile == null) ''
              Environment=FTLCONF_webserver_api_password=${lib.escapeShellArg cfg.webPassword}
            ''}
            Memory=512m
            PidsLimit=500
            Ulimit=nofile=2048:4096
            HealthCmd=curl -fsS http://localhost/admin/ || exit 1
            HealthInterval=30s
            HealthTimeout=10s
            HealthStartPeriod=60s
            HealthRetries=3
            LogDriver=journald
            LogOpt=tag=pihole

            [Service]
            Restart=always
            RestartSec=10
            CPUQuota=100%
            TimeoutStartSec=300

            [Install]
            WantedBy=multi-user.target
          '';

          "containers/systemd/pihole-data.volume".text = ''
            [Volume]
            VolumeName=pihole-data
          '';

          "containers/systemd/pihole-dnsmasq.volume".text = ''
            [Volume]
            VolumeName=pihole-dnsmasq
          '';
        };

        networking.firewall.allowedTCPPorts = [
          cfg.webPort
          cfg.dnsPort
        ];
        networking.firewall.allowedUDPPorts = [ cfg.dnsPort ];
      };
    };
}
