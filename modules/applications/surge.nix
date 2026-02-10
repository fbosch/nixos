_: {
  flake.modules.homeManager."applications/surge" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      cfg = config.services.surge;
      jsonFormat = pkgs.formats.json { };
      serverArgs = lib.escapeShellArgs (
        [
          "server"
          "start"
        ]
        ++ lib.optionals (cfg.port != null) [
          "--port"
          (toString cfg.port)
        ]
        ++ lib.optionals (cfg.outputDir != null) [
          "--output"
          cfg.outputDir
        ]
        ++ lib.optional cfg.noResume "--no-resume"
        ++ lib.optional cfg.exitWhenDone "--exit-when-done"
        ++ cfg.extraArgs
      );
    in
    {
      options.services.surge = {
        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.local.surge;
          description = "Surge package to install and run.";
        };

        autostart = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Start the Surge headless server as a systemd user service.";
        };

        port = lib.mkOption {
          type = lib.types.nullOr lib.types.port;
          default = null;
          description = "Port for Surge server. Null keeps Surge auto-discovery behavior.";
        };

        outputDir = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "${config.home.homeDirectory}/Downloads";
          description = "Default output directory passed to `surge server start --output`.";
        };

        noResume = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Do not auto-resume paused downloads on startup.";
        };

        exitWhenDone = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Exit the server when all downloads complete.";
        };

        extraArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [
            "--batch"
            "${config.home.homeDirectory}/urls.txt"
          ];
          description = "Extra CLI arguments appended to `surge server start`.";
        };

        settings = lib.mkOption {
          inherit (jsonFormat) type;
          default = { };
          example = {
            general.default_download_dir = "/mnt/storage/Downloads";
            connections.max_concurrent_downloads = 5;
          };
          description = "Contents for `~/.config/surge/settings.json`.";
        };
      };

      config = {
        home.packages = [ cfg.package ];

        xdg.configFile."surge/settings.json" = lib.mkIf (cfg.settings != { }) {
          source = jsonFormat.generate "surge-settings.json" cfg.settings;
        };

        systemd.user.services.surge-server = {
          Unit = {
            Description = "Surge background download server";
            After = [ "network-online.target" ];
            Wants = [ "network-online.target" ];
          };

          Service = {
            Type = "simple";
            ExecStart = "${lib.getExe cfg.package} ${serverArgs}";
            Restart = "on-failure";
            RestartSec = "5s";
          };

          Install = lib.mkIf cfg.autostart {
            WantedBy = [ "default.target" ];
          };
        };
      };
    };
}
