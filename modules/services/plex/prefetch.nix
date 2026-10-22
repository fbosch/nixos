{
  flake.modules.nixos."services/plex" =
    { config, lib, pkgs, ... }:
    let
      cfg = config.services.plex-prefetch;
      settings = pkgs.writeText "plex-prefetch.json" (builtins.toJSON {
        inherit (cfg) port prefixMiB rateMiB roots;
        plexPort = config.services.plex.nginx.backendPort;
      });
    in
    {
      options.services.plex-prefetch = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 32403;
          description = "Loopback-only Plex prefetch webhook port.";
        };
        prefixMiB = lib.mkOption {
          type = lib.types.ints.between 1 256;
          default = 256;
          description = "Maximum prefix to read per next-episode job, in MiB.";
        };
        rateMiB = lib.mkOption {
          type = lib.types.ints.between 1 10;
          default = 10;
          description = "Maximum prefetch rate in MiB per second.";
        };
        roots = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "/mnt/nas/video" ];
          description = "Approved media roots. Symlinks beneath these roots are rejected.";
        };
      };

      config = {
        assertions = [
          {
            assertion = config.services.cachefilesd.enable;
            message = "plex-prefetch requires an active FS-Cache configuration.";
          }
          {
            assertion = cfg.roots != [ ] && lib.all (root: lib.hasPrefix "/mnt/nas/video" root && !(lib.hasInfix ".." root) && (root == "/mnt/nas/video" || lib.hasPrefix "/mnt/nas/video/" root)) cfg.roots;
            message = "plex-prefetch roots must remain within the approved video share.";
          }
        ];

        users = {
          groups.plex-prefetch = { };
          users.plex-prefetch = {
            isSystemUser = true;
            group = "plex-prefetch";
            extraGroups = [ "nas-media" ];
          };
        };

        services = {
          startupPolicy.applications.plex.units = lib.mkAfter [
            { name = "plex-prefetch.service"; provider = "nixos"; }
          ];
          exposedPorts = lib.mkAfter [
            { service = "plex-prefetch"; tcpPorts = [ cfg.port ]; }
          ];
        };

        systemd.services.plex-prefetch = {
          description = "Prime bounded next-episode prefixes for Plex";
          wantedBy = [ "multi-user.target" ];
          after = [ "plex.service" "cachefilesd.service" ];
          wants = [ "plex.service" ];
          partOf = [ "plex.service" ];
          unitConfig.RequiresMountsFor = cfg.roots;
          serviceConfig = {
            Type = "simple";
            User = "plex-prefetch";
            Group = "plex-prefetch";
            SupplementaryGroups = [ "nas-media" ];
            ExecStart = "${pkgs.python3}/bin/python3 ${./scripts/prefetch.py} ${settings}";
            # Runtime credentials keep Plex's existing token out of Nix and journal output.
            LoadCredential = [ "plex-preferences:${config.services.plex.dataDir}/Plex Media Server/Preferences.xml" ];
            RuntimeDirectory = "plex-prefetch";
            RuntimeDirectoryMode = "0700";
            UMask = "0077";
            Restart = "on-failure";
            RestartSec = "30s";
            TimeoutStopSec = "10s";
            Nice = 19;
            CPUWeight = 10;
            CPUQuota = "10%";
            IOSchedulingClass = "idle";
            IOWeight = 10;
            MemoryMax = "512M";
            TasksMax = 16;
            NoNewPrivileges = true;
            PrivateTmp = true;
            PrivateDevices = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectProc = "invisible";
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectControlGroups = true;
            RestrictSUIDSGID = true;
            RestrictAddressFamilies = [ "AF_INET" "AF_UNIX" ];
            CapabilityBoundingSet = "";
            ReadOnlyPaths = cfg.roots;
            InaccessiblePaths = [
              "-${config.services.plex.dataDir}"
              "-/var/lib/nas-downloads-cache"
              "-/var/cache/fscache"
              "-/run/secrets"
            ];
          };
        };
        # The receiver deliberately stays on loopback; no LAN firewall port is opened.
      };
    };
}
