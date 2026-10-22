{ config, ... }:
{
  perSystem = { lib, pkgs, system, ... }:
    let
      server = config.flake.nixosConfigurations.rvn-srv.config;
      unit = server.systemd.services.plex-prefetch;
      cfg = server.services.plex-prefetch;
      requirements = {
        "Plex import includes prefetch" = lib.elem "services/plex" config.hosts.rvn-srv.modules
          && server.services.plex.enable
          && server.services.cachefilesd.enable
          && server.services.nasMediaCache.sizeGiB == 10
          && unit.unitConfig.RequiresMountsFor == [ "/mnt/nas/video" ];
        "bounded defaults" = cfg.prefixMiB == 256 && cfg.rateMiB == 10
          && cfg.roots == [ "/mnt/nas/video" ];
        "private runtime credentials" = unit.serviceConfig.User == "plex-prefetch"
          && unit.serviceConfig.LoadCredential == [ "plex-preferences:/var/lib/plex/Plex Media Server/Preferences.xml" ]
          && unit.serviceConfig.RuntimeDirectoryMode == "0700"
          && unit.serviceConfig.UMask == "0077";
        "NAS group and read-only access" = lib.elem "nas-media" server.users.users.plex-prefetch.extraGroups
          && unit.serviceConfig.ReadOnlyPaths == cfg.roots
          && unit.serviceConfig.ProtectSystem == "strict"
          && unit.serviceConfig.NoNewPrivileges;
        "loopback port stays behind the firewall" = cfg.port == 32403
          && !(lib.elem cfg.port server.networking.firewall.allowedTCPPorts)
          && lib.any (entry: entry.service == "plex-prefetch" && entry.tcpPorts == [ cfg.port ]) server.services.exposedPorts;
      };
      healthy = lib.all (value: value) (builtins.attrValues requirements);
    in
    {
      nix-unit.tests.plex-prefetch = lib.mapAttrs
        (_: value: { expr = value; expected = true; })
        requirements;

      checks = lib.mkIf (system == "x86_64-linux") {
        plex-prefetch = assert healthy; pkgs.runCommand "plex-prefetch-checks"
          { nativeBuildInputs = [ pkgs.python3 ]; }
          ''
            export PYTHONDONTWRITEBYTECODE=1
            python3 -m unittest discover -s ${./.}/__tests__ -v
            touch "$out"
          '';
      };
    };
}
