{
  flake.modules = {
    homeManager."applications/surge" =
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
              general.default_download_dir = config.xdg.userDirs.download;
              connections.max_concurrent_downloads = 5;
            };
            description = "Contents for `~/.config/surge/settings.json`.";
          };

        };

        config = {
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
              Restart = if cfg.exitWhenDone then "no" else "always";
              RestartSec = "5s";
            };

            Install = lib.mkIf cfg.autostart {
              WantedBy = [ "default.target" ];
            };
          };
        };
      };

    nixos."applications/surge" =
      { config
      , lib
      , pkgs
      , ...
      }:
      let
        cfg = config.services.surge;
        outputDir = lib.removeSuffix "/" cfg.outputDir;
      in
      {
        options.services.surge = {
          package = lib.mkOption {
            type = lib.types.package;
            default = pkgs.local.surge;
            description = "Surge package to install and confine.";
          };

          outputDir = lib.mkOption {
            type = lib.types.str;
            description = "Absolute download directory available to the Surge service.";
          };
        };

        config = {
          assertions = [
            {
              assertion = lib.hasPrefix "/" cfg.outputDir && cfg.outputDir != "/";
              message = "services.surge.outputDir must be an absolute directory other than /.";
            }
          ];

          environment.systemPackages = [ cfg.package ];

          security.apparmor.policies.surge = lib.mkIf (config.security.apparmor.enable or false) {
            profile = ''
              abi <abi/4.0>,
              include <tunables/global>

              ${lib.getExe cfg.package} flags=(attach_disconnected) {
                include <abstractions/base>
                include <abstractions/nameservice>
                include <abstractions/ssl_certs>

                # Network access for downloads
                network inet stream,
                network inet6 stream,
                network inet dgram,
                network inet6 dgram,
                network unix stream,
                network unix dgram,

                ${lib.getExe cfg.package} mr,

                owner @{HOME}/.config/surge/ rw,
                owner @{HOME}/.config/surge/** rw,

                owner @{HOME}/.local/state/surge/ rw,
                owner @{HOME}/.local/state/surge/** rwk,

                owner /run/user/[0-9]*/surge/ rw,
                owner /run/user/[0-9]*/surge/** rwk,

                owner ${outputDir}/ rw,
                owner ${outputDir}/** rwk,

                /usr/lib/** mr,
                /lib/** mr,

                owner @{PROC}/@{pid}/stat r,
                owner @{PROC}/@{pid}/fd/ r,

                /nix/store/** mr,

                deny /sys/** rw,
                deny @{HOME}/.ssh/** rw,
                deny @{HOME}/.gnupg/** rw,
              }
            '';
          };
        };
      };
  };
}
