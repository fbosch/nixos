_: {
  flake.modules.nixos."services/containers/gluetun" =
    { config
    , lib
    , ...
    }:
    let
      cfg = config.services.gluetun-container;
      publishPorts = map (addr: "PublishPort=${addr}:${toString cfg.port}:8888/tcp") cfg.listenAddresses;
      publishPortBlock = lib.concatStringsSep "\n" publishPorts;
      serverCountries = lib.concatStringsSep "," cfg.serverCountries;
    in
    {
      options.services.gluetun-container = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable Gluetun VPN gateway with HTTP proxy.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8889;
          description = "Host port for Gluetun HTTP proxy.";
        };

        listenAddresses = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "127.0.0.1" ];
          description = "Host addresses to bind the HTTP proxy port on.";
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Open firewall for the configured proxy port.";
        };

        image = lib.mkOption {
          type = lib.types.str;
          default = "docker.io/qmcgaw/gluetun:v3.40.0";
          description = "Container image for Gluetun.";
        };

        envFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "/run/secrets/rendered/gluetun-env";
          description = "Environment file containing VPN credentials (WIREGUARD_PRIVATE_KEY, WIREGUARD_ADDRESSES).";
        };

        timezone = lib.mkOption {
          type = lib.types.str;
          default = "Europe/Copenhagen";
          description = "Timezone for Gluetun logs and scheduling.";
        };

        serverCountries = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "Denmark" ];
          description = "VPN endpoint countries to use.";
        };

        ipVersion = lib.mkOption {
          type = lib.types.enum [
            "ipv4"
            "ipv6"
            "all"
          ];
          default = "all";
          description = "IP family used for VPN endpoint selection.";
        };

        httpProxy = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable Gluetun internal HTTP proxy.";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.envFile != null;
            message = "gluetun-container: envFile is required when enabling Gluetun.";
          }
          {
            assertion = cfg.listenAddresses != [ ];
            message = "gluetun-container: at least one listenAddress must be configured.";
          }
        ];

        services.containerPorts = lib.mkAfter [
          {
            service = "gluetun-container";
            tcpPorts = [ cfg.port ];
          }
        ];

        environment.etc."containers/systemd/gluetun.container".text = ''
          [Unit]
          After=network-online.target
          Wants=network-online.target

          [Container]
          ContainerName=gluetun
          Image=${cfg.image}
          AddCapability=NET_ADMIN
          AddDevice=/dev/net/tun
          ${publishPortBlock}
          Environment=VPN_SERVICE_PROVIDER=mullvad
          Environment=VPN_TYPE=wireguard
          Environment=HTTPPROXY=${if cfg.httpProxy.enable then "on" else "off"}
          Environment=TZ=${lib.escapeShellArg cfg.timezone}
          Environment=SERVER_COUNTRIES=${lib.escapeShellArg serverCountries}
          Environment=IP_VERSION=${cfg.ipVersion}
          EnvironmentFile=${lib.escapeShellArg cfg.envFile}
          Memory=512m
          PidsLimit=200
          Ulimit=nofile=2048:4096
          LogDriver=journald
          LogOpt=tag=gluetun

          [Service]
          Restart=always
          RestartSec=10
          CPUQuota=100%
          TimeoutStartSec=120

          [Install]
          WantedBy=multi-user.target
        '';

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
      };
    };
}
