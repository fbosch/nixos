_: {
  flake.modules.nixos."services/containers/pihole" =
    { config
    , lib
    , pkgs
    , ...
    }:
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
        services.containerPorts = lib.mkAfter [
          {
            service = "pihole-container";
            tcpPorts = [
              config.services.pihole-container.webPort
              config.services.pihole-container.dnsPort
            ];
            udpPorts = [ config.services.pihole-container.dnsPort ];
          }
        ];

        systemd.services.pihole-container = {
          description = "Pi-hole DNS sinkhole";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
            "podman.service"
          ];
          wants = [ "network-online.target" ];
          requires = [ "podman.service" ];

          serviceConfig = {
            Type = "simple";
            Restart = "always";
            RestartSec = "10";
            TimeoutStartSec = "300";
          };

          script = ''
            # Ensure the volumes exist
            ${pkgs.podman}/bin/podman volume create pihole-data || true
            ${pkgs.podman}/bin/podman volume create pihole-dnsmasq || true

            # Remove existing container if it exists
            ${pkgs.podman}/bin/podman rm -f pihole || true

            # Run the container
            ${pkgs.podman}/bin/podman run \
              --name pihole \
              --rm \
              -p ${config.services.pihole-container.listenAddress}:${toString config.services.pihole-container.dnsPort}:53/tcp \
              -p ${config.services.pihole-container.listenAddress}:${toString config.services.pihole-container.dnsPort}:53/udp \
              -p ${config.services.pihole-container.listenAddress}:${toString config.services.pihole-container.webPort}:80/tcp \
              -v pihole-data:/etc/pihole \
              -v pihole-dnsmasq:/etc/dnsmasq.d \
              -e TZ=${lib.escapeShellArg config.services.pihole-container.timezone} \
              -e FTLCONF_dns_listeningMode=${lib.escapeShellArg config.services.pihole-container.dnsListeningMode} \
              ${
                lib.optionalString (config.services.pihole-container.dnsUpstreams != [ ]) ''
                  -e FTLCONF_dns_upstreams=${lib.escapeShellArg (lib.concatStringsSep ";" config.services.pihole-container.dnsUpstreams)} \
                ''
              }${
                lib.optionalString (config.services.pihole-container.dnsForwardMax != null) ''
                  -e FTL_CMD=${lib.escapeShellArg "no-daemon -- --dns-forward-max ${toString config.services.pihole-container.dnsForwardMax}"} \
                ''
              } \
              ${
                lib.optionalString (config.services.pihole-container.webPasswordFile != null) ''
                  --env-file ${lib.escapeShellArg config.services.pihole-container.webPasswordFile} \
                ''
              }${
                lib.optionalString (config.services.pihole-container.webPasswordFile == null) ''
                  -e FTLCONF_webserver_api_password=${lib.escapeShellArg config.services.pihole-container.webPassword} \
                ''
              } \
              --health-cmd="curl -fsS http://localhost/admin/ || exit 1" \
              --health-interval=30s \
              --health-timeout=10s \
              --health-retries=3 \
              --log-driver=journald \
              --log-opt=tag="pihole" \
              pihole/pihole:latest
          '';

          preStop = ''
            ${pkgs.podman}/bin/podman stop -t 10 pihole || true
          '';
        };

        networking.firewall.allowedTCPPorts = [
          config.services.pihole-container.webPort
          config.services.pihole-container.dnsPort
        ];
        networking.firewall.allowedUDPPorts = [ config.services.pihole-container.dnsPort ];
      };
    };
}
