_: {
  flake.modules.nixos."services/containers/gluetun" =
    { config
    , lib
    , ...
    }:
    let
      cfg = config.services.gluetun-container;
      publishPorts = map (addr: "PublishPort=${addr}:${toString cfg.port}:8888/tcp") cfg.listenAddresses;
      controlServerPorts =
        if cfg.controlServer.enable then
          map (addr: "PublishPort=${addr}:${toString cfg.controlServer.port}:8000/tcp") cfg.listenAddresses
        else
          [ ];
      allPublishPorts = publishPorts ++ controlServerPorts;
      publishPortBlock = lib.concatStringsSep "\n" allPublishPorts;
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
          default = "docker.io/qmcgaw/gluetun:v3.41.1";
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

          stealth = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable HTTP proxy stealth mode (removes proxy headers).";
          };
        };

        controlServer = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable Gluetun HTTP control server for API access.";
          };

          port = lib.mkOption {
            type = lib.types.port;
            default = 8000;
            description = "Port for the Gluetun control server.";
          };

          address = lib.mkOption {
            type = lib.types.str;
            default = ":8000";
            description = "Address for the control server (format: 'host:port' or ':port').";
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
            tcpPorts = [ cfg.port ] ++ lib.optional cfg.controlServer.enable cfg.controlServer.port;
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
          ${lib.optionalString cfg.httpProxy.stealth "Environment=HTTPPROXY_STEALTH=on"}
          ${lib.optionalString cfg.controlServer.enable "Environment=HTTP_CONTROL_SERVER_ADDRESS=${lib.escapeShellArg cfg.controlServer.address}"}
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

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall (
          [ cfg.port ] ++ lib.optional cfg.controlServer.enable cfg.controlServer.port
        );
      };
    };
}
