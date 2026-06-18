_: {
  flake.modules.nixos."services/plex" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      cfg = config.services.plex;
      nasRecoveryMountUnits = map (unit: "${unit}.mount") cfg.nasRecovery.mountUnits;
      nasRecoveryAutomountUnits = map (unit: "${unit}.automount") cfg.nasRecovery.mountUnits;
      nasRecoveryUnits = nasRecoveryMountUnits ++ nasRecoveryAutomountUnits;
      nasRecoveryScript = pkgs.writeShellScript "plex-nas-mount-recovery" ''
        set -euo pipefail

        units=(${lib.escapeShellArgs nasRecoveryUnits})
        mount_units=(${lib.escapeShellArgs nasRecoveryMountUnits})
        automount_units=(${lib.escapeShellArgs nasRecoveryAutomountUnits})
        failed=()

        for unit in "''${units[@]}"; do
          result=$(${pkgs.systemd}/bin/systemctl show --property=Result --value "$unit")
          if ${pkgs.systemd}/bin/systemctl is-failed --quiet "$unit" || [ "$result" != success ]; then
            failed+=("$unit")
          fi
        done

        if [ "''${#failed[@]}" -eq 0 ]; then
          echo "No failed Plex NAS mount units."
          exit 0
        fi

        stamp=/run/plex-nas-mount-recovery.last
        now=$(${pkgs.coreutils}/bin/date +%s)
        if [ -e "$stamp" ]; then
          last=$(${pkgs.coreutils}/bin/stat -c %Y "$stamp")
          elapsed=$((now - last))
          if [ "$elapsed" -lt ${toString cfg.nasRecovery.minRetryIntervalSeconds} ]; then
            echo "Skipping Plex NAS mount recovery; last attempt was ''${elapsed}s ago."
            exit 0
          fi
        fi

        if ! ${pkgs.bash}/bin/bash -c 'exec 3<>/dev/tcp/${cfg.nasRecovery.host}/${toString cfg.nasRecovery.port}' 2>/dev/null; then
          echo "Skipping Plex NAS mount recovery; ${cfg.nasRecovery.host}:${toString cfg.nasRecovery.port} is unreachable."
          exit 0
        fi

        ${pkgs.coreutils}/bin/touch "$stamp"

        echo "Recovering failed Plex NAS units: ''${failed[*]}"
        ${pkgs.systemd}/bin/systemctl reset-failed "''${failed[@]}"
        ${pkgs.systemd}/bin/systemctl start "''${automount_units[@]}"

        for unit in "''${mount_units[@]}"; do
          ${pkgs.systemd}/bin/systemctl start "$unit"
        done

        ${pkgs.systemd}/bin/systemctl --no-pager --full status "''${units[@]}" || true
      '';
    in
    {
      options.services.plex = {
        transcodeInRAM = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Store Plex transcoding cache in RAM (tmpfs) for better performance and reduced disk wear.";
        };

        transcodeRAMSize = lib.mkOption {
          type = lib.types.str;
          default = "4G";
          example = "8G";
          description = "Size of tmpfs for transcode cache (2G for 8GB RAM, 4G for 16GB RAM, 8G for 32GB+ RAM).";
        };

        nginx = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable nginx reverse proxy with caching for Plex.";
          };

          port = lib.mkOption {
            type = lib.types.port;
            default = 32401;
            description = "Port for nginx reverse proxy.";
          };

          backendPort = lib.mkOption {
            type = lib.types.port;
            default = 32400;
            description = "Backend Plex port.";
          };

          cacheSize = lib.mkOption {
            type = lib.types.str;
            default = "2g";
            description = "Maximum size of nginx cache for Plex static content.";
          };

          cacheTTL = lib.mkOption {
            type = lib.types.str;
            default = "24h";
            description = "Time to cache static content.";
          };
        };

        nasRecovery = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable periodic recovery for failed NAS media mounts used by Plex.";
          };

          host = lib.mkOption {
            type = lib.types.str;
            default = "rvn-nas";
            description = "NAS host checked for SMB reachability before recovery.";
          };

          port = lib.mkOption {
            type = lib.types.port;
            default = 445;
            description = "NAS SMB port checked before recovery.";
          };

          interval = lib.mkOption {
            type = lib.types.str;
            default = "5m";
            description = "How often to check for failed Plex NAS mount units.";
          };

          minRetryIntervalSeconds = lib.mkOption {
            type = lib.types.ints.positive;
            default = 300;
            description = "Minimum seconds between recovery attempts once failed units are detected.";
          };

          mountUnits = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "mnt-nas-video"
              "mnt-nas-LaCie"
            ];
            description = "Systemd mount unit prefixes to recover, without .mount or .automount suffixes.";
          };
        };
      };

      config = {
        services = {
          plex = {
            enable = lib.mkDefault true;
            openFirewall = lib.mkDefault true;
          };

          # Nginx reverse proxy with caching
          nginx = lib.mkIf cfg.nginx.enable {
            enable = true;

            # Recommended settings for reverse proxy
            recommendedProxySettings = true;
            recommendedOptimisation = true;
            recommendedGzipSettings = true;

            # Cache path configuration
            appendHttpConfig = ''
              proxy_cache_path /var/cache/nginx/plex
                levels=1:2
                keys_zone=plex_cache:10m
                max_size=${cfg.nginx.cacheSize}
                inactive=${cfg.nginx.cacheTTL}
                use_temp_path=off;
            '';

            upstreams.plex = {
              servers."127.0.0.1:${toString cfg.nginx.backendPort}" = { };
            };

            virtualHosts."plex-proxy" = {
              listen = [
                {
                  addr = "0.0.0.0";
                  inherit (cfg.nginx) port;
                }
              ];

              locations = {
                # Cache static icons/favicons with long TTL (rarely change)
                "~ ^/web/(static|favicon)" = {
                  proxyPass = "http://plex";
                  extraConfig = ''
                    proxy_cache plex_cache;
                    proxy_cache_valid 200 7d;
                    proxy_cache_key "$scheme$request_method$host$request_uri";
                    add_header X-Cache-Status $upstream_cache_status;
                    add_header Cache-Control "public, max-age=604800";

                    # Enable buffering for caching
                    proxy_buffering on;

                    # Headers
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto $scheme;
                  '';
                };

                # Cache library metadata (posters, artwork, show/movie info)
                "~ ^/library/(metadata|parts)" = {
                  proxyPass = "http://plex";
                  extraConfig = ''
                    proxy_cache plex_cache;
                    proxy_cache_valid 200 1h;
                    proxy_cache_key "$scheme$request_method$host$request_uri$http_x_plex_token";
                    proxy_cache_bypass $http_upgrade;
                    add_header X-Cache-Status $upstream_cache_status;

                    # Ignore Plex's no-cache headers for metadata
                    proxy_ignore_headers Cache-Control Expires;
                    add_header Cache-Control "private, max-age=3600";

                    # Enable buffering for caching
                    proxy_buffering on;
                    proxy_buffer_size 8k;
                    proxy_buffers 16 8k;

                    # Headers (include Plex token for authenticated requests)
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto $scheme;
                    proxy_set_header X-Plex-Token $http_x_plex_token;
                  '';
                };

                # Cache static content (web UI, images, resources)
                "~ ^/(web|photo|:/resources)" = {
                  proxyPass = "http://plex";
                  extraConfig = ''
                    proxy_cache plex_cache;
                    proxy_cache_valid 200 ${cfg.nginx.cacheTTL};
                    proxy_cache_key "$scheme$request_method$host$request_uri";
                    proxy_cache_bypass $http_upgrade;
                    add_header X-Cache-Status $upstream_cache_status;

                    # Ignore Plex's cache control headers and force caching
                    proxy_ignore_headers Cache-Control Expires Set-Cookie;
                    proxy_hide_header Cache-Control;
                    add_header Cache-Control "public, max-age=86400";

                    # Enable buffering for caching (required for proxy_cache to work)
                    # Larger buffers for big JS bundles (3.5MB)
                    proxy_buffering on;
                    proxy_buffer_size 8k;
                    proxy_buffers 32 8k;
                    proxy_busy_buffers_size 16k;

                    # Headers
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto $scheme;
                    proxy_set_header X-Plex-Client-Identifier $http_x_plex_client_identifier;
                  '';
                };

                # Don't cache dynamic/streaming content
                "/" = {
                  proxyPass = "http://plex";
                  extraConfig = ''
                    # Disable caching for streaming
                    proxy_no_cache 1;
                    proxy_cache_bypass 1;

                    # Disable buffering for streaming
                    proxy_buffering off;

                    # WebSocket support
                    proxy_http_version 1.1;
                    proxy_set_header Upgrade $http_upgrade;
                    proxy_set_header Connection "upgrade";

                    # Headers
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto $scheme;
                    proxy_set_header X-Plex-Client-Identifier $http_x_plex_client_identifier;

                    # Timeouts for long-running streams
                    proxy_read_timeout 3600s;
                    proxy_send_timeout 3600s;
                  '';
                };
              };
            };
          };

          # Ananicy rules for Plex processes
          ananicy.customRules = [
            {
              name = "Plex Media Serv";
              type = "Player-Video";
              nice = -5;
              ioclass = "best-effort";
              ionice = 0;
            }
            {
              name = "Plex Tuner Serv";
              type = "Player-Video";
              nice = -3;
            }
            {
              name = "Plex Script Hos";
              nice = 0;
            }
          ];
        };

        users.users.plex.extraGroups = [ "users" ];

        systemd = {
          services = {
            plex.serviceConfig = {
              Nice = -10;
              CPUWeight = 1000;
              IOSchedulingClass = "best-effort";
              IOSchedulingPriority = 0;
              IOWeight = 1000;
              OOMScoreAdjust = -900;
              MemoryLow = "2G";
            };

            plex-nas-mount-recovery = lib.mkIf cfg.nasRecovery.enable {
              description = "Recover failed Plex NAS media mounts";
              after = [ "network-online.target" ];
              wants = [ "network-online.target" ];
              serviceConfig = {
                Type = "oneshot";
                ExecStart = nasRecoveryScript;
              };
            };
          };

          timers.plex-nas-mount-recovery = lib.mkIf cfg.nasRecovery.enable {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnBootSec = cfg.nasRecovery.interval;
              OnUnitActiveSec = cfg.nasRecovery.interval;
              RandomizedDelaySec = "30s";
            };
          };

          tmpfiles.rules = lib.mkIf cfg.nginx.enable [
            "d /var/cache/nginx/plex 0750 nginx nginx -"
          ];
        };

        fileSystems."/var/lib/plex/Plex Media Server/Cache/Transcode" = lib.mkIf cfg.transcodeInRAM {
          device = "tmpfs";
          fsType = "tmpfs";
          options = [
            "defaults"
            "size=${cfg.transcodeRAMSize}"
            "mode=0755"
            "uid=plex"
            "gid=plex"
          ];
        };

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.nginx.enable [
          cfg.nginx.port
        ];
      };
    };
}
