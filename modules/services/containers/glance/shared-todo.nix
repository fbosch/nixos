_: {
  perSystem = { pkgs, ... }: {
    checks.glance-shared-todo =
      pkgs.runCommand "glance-shared-todo-tests"
        {
          nativeBuildInputs = [ pkgs.bun ];
        }
        ''
          cp -r ${./shared-todo} source
          chmod -R u+w source
          cd source
          bun test
          touch $out
        '';
  };

  flake.modules.nixos."services/glance-shared-todo" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      cfg = config.services.glance-shared-todo;
    in
    {
      options.services.glance-shared-todo = {
        listenAddress = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Loopback address used by the local nginx frontend";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8091;
          description = "TCP port for the shared Glance todo API";
        };

        mcpListenAddress = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Address used by the shared todo MCP listener";
        };

        mcpPort = lib.mkOption {
          type = lib.types.port;
          default = 8092;
          description = "TCP port for the shared todo MCP listener";
        };

        allowedOrigin = lib.mkOption {
          type = lib.types.str;
          default = "https://glance.corvus-corax.synology.me";
          description = "Exact browser origin allowed to mutate the task list";
        };
      };

      config = {
        services = {
          startupPolicy.applications.glance.units = lib.mkAfter [
            {
              name = "glance-shared-todo.service";
              provider = "nixos";
            }
          ];

          exposedPorts = lib.mkAfter [
            {
              service = "glance-shared-todo";
              tcpPorts = [
                cfg.port
                cfg.mcpPort
              ];
            }
          ];
        };

        systemd.services.glance-shared-todo = {
          description = "Shared task storage for Glance";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          environment = {
            GLANCE_SHARED_TODO_ALLOWED_ORIGIN = cfg.allowedOrigin;
            GLANCE_SHARED_TODO_DATABASE = "/var/lib/glance-shared-todo/todo.sqlite";
            GLANCE_SHARED_TODO_HOST = cfg.listenAddress;
            GLANCE_SHARED_TODO_MCP_HOST = cfg.mcpListenAddress;
            GLANCE_SHARED_TODO_MCP_PORT = toString cfg.mcpPort;
            GLANCE_SHARED_TODO_PORT = toString cfg.port;
          };
          serviceConfig = {
            ExecStart = "${pkgs.bun}/bin/bun ${./shared-todo}/server.ts";
            DynamicUser = true;
            StateDirectory = "glance-shared-todo";
            StateDirectoryMode = "0750";
            Restart = "on-failure";
            RestartSec = "5s";
            NoNewPrivileges = true;
            PrivateDevices = true;
            PrivateTmp = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectSystem = "strict";
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
            ];
            RestrictNamespaces = true;
            RestrictRealtime = true;
            SystemCallArchitectures = "native";
            UMask = "0077";
          };
        };

        networking.firewall.allowedTCPPorts = [ cfg.mcpPort ];

        assertions = [
          {
            assertion = cfg.listenAddress != cfg.mcpListenAddress || cfg.port != cfg.mcpPort;
            message = "glance-shared-todo: API and MCP listeners must use different addresses or ports";
          }
        ];
      };
    };
}
