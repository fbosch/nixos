_: {
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
              general.default_download_dir = "/mnt/storage/Downloads";
              connections.max_concurrent_downloads = 5;
            };
            description = "Contents for `~/.config/surge/settings.json`.";
          };

          enableAppArmor = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable AppArmor confinement for Surge (requires NixOS with AppArmor enabled).";
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

    # NixOS-level AppArmor profile for Surge
    nixos."applications/surge" =
      { config
      , lib
      , pkgs
      , ...
      }:
      let
        # Extract AppArmor enablement from home-manager user config
        hmUsers = config.home-manager.users or { };
        user = config.flake.meta.user.username or null;
        surgeCfg = if user != null && hmUsers ? ${user} then hmUsers.${user}.services.surge or { } else { };
        enableAppArmor = surgeCfg.enableAppArmor or false;
      in
      {
        config = lib.mkIf enableAppArmor {
          security.apparmor.policies."surge" = {
            enable = true;
            profile = ''
              abi <abi/4.0>,
              include <tunables/global>

              ${lib.getExe pkgs.local.surge} flags=(attach_disconnected) {
                include <abstractions/base>
                include <abstractions/nameservice>
                include <abstractions/ssl_certs>

                # Network access for downloads
                network inet stream,
                network inet6 stream,
                network inet dgram,
                network inet6 dgram,

                # Surge binary
                ${lib.getExe pkgs.local.surge} mr,

                # Config directory
                owner @{HOME}/.config/surge/ rw,
                owner @{HOME}/.config/surge/** rw,

                # State directory (database, logs, token)
                owner @{HOME}/.local/state/surge/ rw,
                owner @{HOME}/.local/state/surge/** rwk,

                # Runtime directory (PID, port, lock files)
                owner /run/user/[0-9]*/surge/ rw,
                owner /run/user/[0-9]*/surge/** rwk,

                # Download directories (user home + common locations)
                owner @{HOME}/Downloads/ rw,
                owner @{HOME}/Downloads/** rw,
                owner @{HOME}/** rw,
                owner /mnt/** rw,

                # Batch files (URL lists)
                owner @{HOME}/** r,

                # Temporary download files
                owner @{HOME}/**{.surge,.tmp} rw,

                # System libraries and shared objects
                /usr/lib/** mr,
                /lib/** mr,

                # /proc access for own process
                owner @{PROC}/@{pid}/stat r,
                owner @{PROC}/@{pid}/fd/ r,

                # Clipboard tools (optional, for clipboard monitoring)
                /usr/bin/xclip ix,
                /usr/bin/xsel ix,
                /usr/bin/wl-copy ix,
                /usr/bin/wl-paste ix,

                # Nix store (for Go runtime and dependencies)
                /nix/store/** mr,

                # Deny unnecessary access
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
