_: {
  flake.modules.nixos."services/tinyproxy" =
    { config
    , lib
    , ...
    }:
    let
      cfg = config.services.tinyproxy;
    in
    {
      options.services.tinyproxy = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 8888;
          description = "Port to listen on for proxy connections.";
        };

        listenAddress = lib.mkOption {
          type = lib.types.str;
          default = "0.0.0.0";
          description = "Address to bind the proxy server to.";
        };

        allowedClients = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "192.168.1.0/24" ];
          description = "Allowed client IP addresses or CIDR ranges.";
        };

        maxClients = lib.mkOption {
          type = lib.types.int;
          default = 100;
          description = "Maximum number of concurrent connections.";
        };

        timeout = lib.mkOption {
          type = lib.types.int;
          default = 600;
          description = "Timeout in seconds for idle connections.";
        };

        logLevel = lib.mkOption {
          type = lib.types.enum [
            "Critical"
            "Error"
            "Warning"
            "Notice"
            "Connect"
            "Info"
          ];
          default = "Info";
          description = "Logging verbosity level.";
        };

        anonymize = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Remove client identifying headers (User-Agent, Referer, Cookie).";
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Open firewall port for the proxy.";
        };
      };

      config = {
        services.tinyproxy = {
          enable = lib.mkDefault true;
          settings = lib.mkMerge [
            {
              Port = cfg.port;
              Listen = cfg.listenAddress;
              Timeout = cfg.timeout;
              MaxClients = cfg.maxClients;
              LogLevel = cfg.logLevel;
              Allow = cfg.allowedClients;
              DisableViaHeader = cfg.anonymize;
            }
            (lib.mkIf cfg.anonymize {
              Anonymous = [
                "User-Agent"
                "Referer"
                "Cookie"
                "Set-Cookie"
              ];
            })
          ];
        };

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
      };
    };
}
