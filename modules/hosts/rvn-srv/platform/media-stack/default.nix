{
  flake.modules.nixos."hosts/rvn-srv/platform" =
    { lib, pkgs, ... }:
    let
      plexNasMountRecovery = pkgs.writeShellApplication {
        name = "plex-nas-mount-recovery";
        runtimeInputs = with pkgs; [
          bash
          coreutils
          systemd
        ];
        text = builtins.readFile ./scripts/plex-nas-mount-recovery.sh;
      };
      recoverPlexMounts = pkgs.writeShellApplication {
        name = "recover-plex-mounts";
        runtimeInputs = with pkgs; [
          sudo
          systemd
          util-linux
        ];
        text = ''
          set -euo pipefail

          sudo systemctl start plex-nas-mount-recovery.service
          systemctl status plex-nas-mount-recovery.service --no-pager || true
          for mountpoint in /mnt/nas/video /mnt/nas/LaCie '/var/lib/plex/Plex Media Server/Cache/Transcode'; do
            findmnt --target "$mountpoint"
          done
        '';
      };
    in
    {
      services = {
        plex.nginx.port = 32402;

        linkwarden-container = {
          port = 3100;
          nextauthUrl = "https://linkwarden.corvus-corax.synology.me";
          disableRegistration = true; # Set to true after first user registration
          cpus = "2.0";
          memory = "4g";
          memoryReservation = "2g";
          shmSize = "256m"; # Important for PDF/screenshot generation
          meilisearch.memory = "1g"; # Meilisearch was hitting OOM at 512m.
        };

        rdtclient = {
          port = 6500;
          downloadPath = "/mnt/nas/downloads";
          tempDownloadPath = "/mnt/nas/downloads/rdtclient-temp";
          timezone = "Europe/Copenhagen";
          userId = 1000;
          groupId = 1000;
          cpus = "0.25";
          memory = "4g";
        };
      };

      environment.systemPackages = [ recoverPlexMounts ];

      systemd = {
        services.plex-nas-mount-recovery = {
          description = "Recover failed Plex NAS media mounts";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${plexNasMountRecovery}/bin/plex-nas-mount-recovery";
          };
        };

        timers.plex-nas-mount-recovery = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "5m";
            OnUnitActiveSec = "5m";
            RandomizedDelaySec = "30s";
          };
        };
      };
    };
}
