_: {
  flake.modules.nixos."services/containers/dozzle" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      cfg = config.services.dozzle;
    in
    {
      options.services.dozzle = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 8090;
          description = "Port for Dozzle web interface";
        };

        hostname = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Custom hostname for display in Dozzle UI (defaults to system hostname)";
        };

        enableActions = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable container actions (stop, start, restart). Disabled by default for security.";
        };

        enableShell = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable shell access to containers. Disabled by default for security.";
        };

        filter = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Filter to show only specific containers (e.g., 'name=myapp' or 'label=com.example.group=web')";
        };

        authProvider = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.enum [
              "simple"
              "forward-proxy"
              "none"
            ]
          );
          default = null;
          description = "Authentication provider: simple (file-based), forward-proxy (e.g., Authelia), or none";
        };

        noAnalytics = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Disable anonymous analytics";
        };
      };

      config = {
        # Ensure Podman socket is available
        virtualisation.podman = {
          enable = true;
          dockerCompat = true;
        };

        # Create engine-id file required by Dozzle when using Podman
        systemd.tmpfiles.rules = [
          # Create /var/lib/docker directory
          "d /var/lib/docker 0755 root root -"
          # Generate engine-id from machine-id for consistency across reboots
          # This creates a stable UUID based on the system's machine-id
          "f /var/lib/docker/engine-id 0644 root root - $(${pkgs.util-linux}/bin/uuidgen -s -n @dns -N $(cat /etc/machine-id))"
        ];

        environment.etc = {
          "containers/systemd/dozzle.container".text =
            let
              envVars = lib.concatStringsSep "\n" (
                lib.filter (x: x != null) [
                  (lib.optionalString
                    (
                      cfg.hostname != null
                    ) "Environment=DOZZLE_HOSTNAME=${lib.escapeShellArg cfg.hostname}")
                  (lib.optionalString cfg.enableActions "Environment=DOZZLE_ENABLE_ACTIONS=true")
                  (lib.optionalString cfg.enableShell "Environment=DOZZLE_ENABLE_SHELL=true")
                  (lib.optionalString
                    (
                      cfg.filter != null
                    ) "Environment=DOZZLE_FILTER=${lib.escapeShellArg cfg.filter}")
                  (lib.optionalString
                    (
                      cfg.authProvider != null
                    ) "Environment=DOZZLE_AUTH_PROVIDER=${cfg.authProvider}")
                  (lib.optionalString cfg.noAnalytics "Environment=DOZZLE_NO_ANALYTICS=true")
                ]
              );
            in
            ''
              [Unit]
              Description=Dozzle - Real-time container log viewer
              After=network-online.target podman.socket
              Wants=network-online.target
              Requires=podman.socket

              [Container]
              ContainerName=dozzle
              Image=docker.io/amir20/dozzle:latest
              PublishPort=${toString cfg.port}:8080
              Volume=/run/podman/podman.sock:/var/run/docker.sock:ro
              Volume=/var/lib/docker/engine-id:/var/lib/docker/engine-id:ro
              ${envVars}
              Memory=256m
              PidsLimit=200
              Ulimit=nofile=2048:4096
              HealthCmd=wget --no-verbose --tries=1 --spider http://localhost:8080/healthcheck || exit 1
              HealthInterval=30s
              HealthTimeout=10s
              HealthStartPeriod=10s
              HealthRetries=3
              LogDriver=journald
              LogOpt=tag=dozzle

              [Service]
              Restart=always
              RestartSec=10
              CPUQuota=50%
              TimeoutStartSec=60

              [Install]
              WantedBy=multi-user.target
            '';
        };

        networking.firewall.allowedTCPPorts = [ cfg.port ];
      };
    };
}
