_:
{
  flake.modules.nixos."services/<SERVICE-NAME>" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      cfg = config.services.<SERVICE-NAME>;
      in
      {
      options.services.<SERVICE-NAME> = {
      enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable <SERVICE-NAME> service";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8080;
        description = "Port for <SERVICE-NAME> web interface";
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/<SERVICE-NAME>";
        description = "Data directory for <SERVICE-NAME>";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "<SERVICE-NAME>";
        description = "User account for <SERVICE-NAME> service";
      };

      group = lib.mkOption {
        type = lib.types.str;
        default = "<SERVICE-NAME>";
        description = "Group for <SERVICE-NAME> service";
      };
      };

      config = lib.mkIf cfg.enable {
        # Create service user and group
        users.users.${cfg.user} = {
          isSystemUser = true;
          group = cfg.group;
          home = cfg.dataDir;
          createHome = true;
        };

        users.groups.${cfg.group} = { };

        # Systemd service
        systemd.services.<SERVICE-NAME> = {
        description = "<SERVICE-NAME> Service";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];

        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          WorkingDirectory = cfg.dataDir;
          Restart = "always";
          RestartSec = "10";
        };

        script = ''
          ${pkgs.<PACKAGE-NAME>}/bin/<SERVICE-NAME> \
            --port ${toString cfg.port} \
            --data-dir ${cfg.dataDir}
        '';
      };

      # Open firewall port
      networking.firewall.allowedTCPPorts = [ cfg.port ];
      };
      };
      }
