{ inputs, ... }:
let
  homeManagerSurge =
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

  nixosSurge =
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
in
{
  flake.modules = {
    homeManager."applications/surge" = homeManagerSurge;
    nixos."applications/surge" = nixosSurge;
  };

  perSystem =
    { config, lib, pkgs, ... }:
    let
      surgeHomeConfig =
        exitWhenDone:
        (inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            homeManagerSurge
            {
              home = {
                username = "tester";
                homeDirectory = "/home/tester";
                stateVersion = "25.05";
              };
              systemd.user.enable = false;
              services.surge = {
                package = pkgs.hello;
                port = 8080;
                outputDir = "/var/lib/surge-output";
                noResume = true;
                inherit exitWhenDone;
                extraArgs = [
                  "--batch"
                  "/tmp/urls.txt"
                ];
              };
            }
          ];
        }).config;
      surgeNixosConfig =
        (lib.evalModules {
          specialArgs = { inherit pkgs; };
          modules = [
            {
              options = {
                assertions = lib.mkOption {
                  type = lib.types.listOf lib.types.anything;
                  default = [ ];
                };
                environment.systemPackages = lib.mkOption {
                  type = lib.types.listOf lib.types.anything;
                  default = [ ];
                };
                security.apparmor = {
                  enable = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                  };
                  policies = lib.mkOption {
                    type = lib.types.attrsOf lib.types.anything;
                    default = { };
                  };
                };
              };
            }
            nixosSurge
            {
              security.apparmor.enable = true;
              services.surge = {
                package = pkgs.hello;
                outputDir = "/var/lib/surge-output/";
              };
            }
          ];
        }).config;
      surgeTestExe = builtins.unsafeDiscardStringContext (lib.getExe pkgs.hello);
      surgeProfile = surgeNixosConfig.security.apparmor.policies.surge.profile;
      surgeProfileLines = lib.splitString "\n" surgeProfile;
      defaultSurgePackage = config.packages.surge;
      isBroadWriteRule =
        rule:
        let
          matches = builtins.match "^[[:space:]]*(owner[[:space:]]+)?([^[:space:]]+)[[:space:]]+([^,[:space:]]+),[[:space:]]*$" rule;
        in
        if matches == null then
          false
        else
          let
            path = builtins.elemAt matches 1;
            permissions = builtins.elemAt matches 2;
          in
          (path == "@{HOME}/**" || path == "/mnt/**")
          && (lib.hasInfix "w" permissions || lib.hasInfix "a" permissions);
    in
    {
      nix-unit.tests.surgeService = {
        testDefaultPackageUsesUpstreamSource = {
          expr = defaultSurgePackage.src.outPath;
          expected = inputs.surge.outPath;
        };
        testDefaultPackageUsesPinnedVersion = {
          expr = defaultSurgePackage.version;
          expected = "0.12.0";
        };
        testStaleUpstreamVendorTreeIsDiscarded = {
          expr = lib.hasInfix "rm -rf vendor" defaultSurgePackage.postPatch;
          expected = true;
        };
        testExitWhenDoneDoesNotRestart = {
          expr = (surgeHomeConfig true).systemd.user.services.surge-server.Service.Restart;
          expected = "no";
        };
        testIncompleteDownloadsRestartAlways = {
          expr = (surgeHomeConfig false).systemd.user.services.surge-server.Service.Restart;
          expected = "always";
        };
        testServiceUsesConfiguredPackage = {
          expr = (surgeHomeConfig true).systemd.user.services.surge-server.Service.ExecStart;
          expected = [
            "${lib.getExe pkgs.hello} server start --port 8080 --output /var/lib/surge-output --no-resume --exit-when-done --batch /tmp/urls.txt"
          ];
        };
        testAppArmorUsesConfiguredPackage = {
          expr = lib.hasInfix "${surgeTestExe} flags=(attach_disconnected)" surgeProfile;
          expected = true;
        };
        testAppArmorAllowsOnlyConfiguredOutputRoot = {
          expr =
            lib.all (rule: lib.hasInfix rule surgeProfile) [
              "owner /var/lib/surge-output/ rw,"
              "owner /var/lib/surge-output/** rwk,"
            ]
            && lib.hasInfix "/var/lib/surge-output//" surgeProfile == false;
          expected = true;
        };
        testAppArmorHasNoBroadHomeOrMountWrites = {
          expr = lib.any isBroadWriteRule surgeProfileLines;
          expected = false;
        };
        testAppArmorDeniesSensitivePaths = {
          expr = lib.all (rule: lib.hasInfix rule surgeProfile) [
            "deny @{HOME}/.ssh/** rw,"
            "deny @{HOME}/.gnupg/** rw,"
          ];
          expected = true;
        };
      };
    };
}
