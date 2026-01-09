{
  flake.modules.homeManager.applications =
    { config, pkgs, lib, ... }:
    let
      # Toggle between psd (profile-sync-daemon) and manual tmpfs setup
      useProfileSyncDaemon = false;
    in
    {
      home.packages = with pkgs; [ local.helium-browser ];

      xdg.mimeApps.defaultApplications = {
        "text/html" = [ "io.github.zen_browser.zen.desktop" ];
        "x-scheme-handler/http" = [ "io.github.zen_browser.zen.desktop" ];
        "x-scheme-handler/https" = [ "io.github.zen_browser.zen.desktop" ];
        "x-scheme-handler/about" = [ "io.github.zen_browser.zen.desktop" ];
        "x-scheme-handler/unknown" = [ "io.github.zen_browser.zen.desktop" ];
      };

      # Option 1: Profile-sync-daemon (supports multiple browsers automatically)
      services.psd = lib.mkIf useProfileSyncDaemon {
        enable = true;
        resyncTimer = "30min";
      };

      # Option 2: Manual tmpfs setup using systemd for Zen Browser
      # More reliable since psd might not recognize Zen Browser yet
      systemd.user = {
        services.zen-browser-profile-sync = lib.mkIf (!useProfileSyncDaemon) {
          Unit = {
            Description = "Zen Browser profile sync to RAM";
            Before = [ "default.target" ];
          };

          Service = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "zen-sync-start" ''
              set -euo pipefail
              
              # Zen Browser stores profiles in ~/.zen (like Firefox uses ~/.mozilla/firefox)
              ZEN_DIR="$HOME/.zen"
              
              # Find the default profile
              if [ ! -d "$ZEN_DIR" ]; then
                echo "Zen Browser profile directory not found. Skipping sync."
                exit 0
              fi
              
              # Find profile directories (usually named like xyz.default or xyz.default-release)
              for profile_path in "$ZEN_DIR"/*.default*; do
                if [ ! -d "$profile_path" ]; then
                  continue
                fi
                
                profile=$(basename "$profile_path")
                static="$ZEN_DIR/static-$profile"
                volatile="/dev/shm/zen-$profile-$USER"
                
                # Create tmpfs directory
                if [ ! -d "$volatile" ]; then
                  mkdir -m0700 "$volatile"
                fi
                
                # Move profile to static location and create symlink
                if [ ! -L "$profile_path" ] || [ "$(readlink "$profile_path")" != "$volatile" ]; then
                  if [ ! -d "$static" ]; then
                    mv "$profile_path" "$static"
                  fi
                  ln -sf "$volatile" "$profile_path"
                fi
                
                # Sync from disk to RAM
                if [ -e "$volatile/.unpacked" ]; then
                  ${pkgs.rsync}/bin/rsync -a --delete --exclude .unpacked "$volatile/" "$static/"
                else
                  ${pkgs.rsync}/bin/rsync -a "$static/" "$volatile/"
                  touch "$volatile/.unpacked"
                fi
                
                echo "Synced Zen Browser profile: $profile"
              done
            '';

            ExecStop = pkgs.writeShellScript "zen-sync-stop" ''
              set -euo pipefail
              
              ZEN_DIR="$HOME/.zen"
              
              if [ ! -d "$ZEN_DIR" ]; then
                exit 0
              fi
              
              for profile_path in "$ZEN_DIR"/*.default*; do
                if [ ! -L "$profile_path" ]; then
                  continue
                fi
                
                profile=$(basename "$profile_path")
                static="$ZEN_DIR/static-$profile"
                volatile="/dev/shm/zen-$profile-$USER"
                
                if [ -d "$volatile" ] && [ -d "$static" ]; then
                  ${pkgs.rsync}/bin/rsync -a --delete --exclude .unpacked "$volatile/" "$static/"
                  echo "Synced Zen Browser profile back to disk: $profile"
                fi
              done
            '';
          };

          Install.WantedBy = [ "default.target" ];
        };

        # Periodic sync timer (every 30 minutes)
        timers.zen-browser-profile-sync-periodic = lib.mkIf (!useProfileSyncDaemon) {
          Unit.Description = "Periodic sync of Zen Browser profile from RAM to disk";

          Timer = {
            OnBootSec = "30min";
            OnUnitActiveSec = "30min";
            Unit = "zen-browser-profile-sync-periodic.service";
          };

          Install.WantedBy = [ "timers.target" ];
        };

        services.zen-browser-profile-sync-periodic = lib.mkIf (!useProfileSyncDaemon) {
          Unit.Description = "Periodic sync of Zen Browser profile from RAM to disk";

          Service = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "zen-periodic-sync" ''
              set -euo pipefail
              
              ZEN_DIR="$HOME/.zen"
              
              if [ ! -d "$ZEN_DIR" ]; then
                exit 0
              fi
              
              for profile_path in "$ZEN_DIR"/*.default*; do
                if [ ! -L "$profile_path" ]; then
                  continue
                fi
                
                profile=$(basename "$profile_path")
                static="$ZEN_DIR/static-$profile"
                volatile="/dev/shm/zen-$profile-$USER"
                
                if [ -d "$volatile" ] && [ -d "$static" ]; then
                  ${pkgs.rsync}/bin/rsync -a --delete --exclude .unpacked "$volatile/" "$static/"
                  echo "[$(date)] Periodic sync: $profile"
                fi
              done
            '';
          };
        };
      };
    };
}
