{ config, ... }:
{
  flake.modules.nixos."services/plex" =
    { config
    , lib
    , ...
    }:
    let
      cfg = config.services.plex;
    in
    {
      options.services.plex = {
        transcodeInRAM = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Store Plex transcoding cache in RAM (tmpfs) for better performance.
            Recommended for systems with sufficient RAM (8GB+).
            Reduces disk wear and significantly speeds up transcoding.
          '';
        };

        transcodeRAMSize = lib.mkOption {
          type = lib.types.str;
          default = "4G";
          example = "8G";
          description = ''
            Size of tmpfs for transcode cache when transcodeInRAM is enabled.

            Recommended sizes:
            - 2G: Systems with 8GB RAM (1 concurrent 1080p stream)
            - 4G: Systems with 16GB RAM (2 concurrent 1080p streams)
            - 8G: Systems with 32GB+ RAM (4K transcoding or 4+ streams)

            Note: tmpfs grows on-demand and only uses RAM when actively transcoding.
          '';
        };

        nginx = {
          enable = lib.mkEnableOption "nginx reverse proxy with caching for Plex";

          port = lib.mkOption {
            type = lib.types.port;
            default = 32401;
            description = "Port for nginx reverse proxy (use different from Plex's 32400)";
          };

          backendPort = lib.mkOption {
            type = lib.types.port;
            default = 32400;
            description = "Backend Plex port";
          };

          cacheSize = lib.mkOption {
            type = lib.types.str;
            default = "2g";
            description = "Maximum size of nginx cache for Plex static content";
          };

          cacheTTL = lib.mkOption {
            type = lib.types.str;
            default = "24h";
            description = "Time to cache static content (images, CSS, JS)";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        services.plex.openFirewall = lib.mkDefault true;

        # Plex transcoding in RAM for faster performance and less disk wear
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

        # Nginx reverse proxy with caching
        services.nginx = lib.mkIf cfg.nginx.enable {
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
                port = cfg.nginx.port;
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

        # Create cache directory
        systemd.tmpfiles.rules = lib.mkIf cfg.nginx.enable [
          "d /var/cache/nginx/plex 0750 nginx nginx -"
        ];

        # Open firewall for nginx proxy port
        networking.firewall.allowedTCPPorts = lib.mkIf cfg.nginx.enable [
          cfg.nginx.port
        ];

        # Ananicy rules for Plex processes
        services.ananicy.customRules = [
          # Main Plex Media Server - highest priority for smooth playback/transcoding
          {
            name = "Plex Media Serv";
            type = "Player-Video";
            nice = -5;
            ioclass = "best-effort";
            ionice = 0;
          }
          # Plex Tuner Service - medium-high priority for live TV
          {
            name = "Plex Tuner Serv";
            type = "Player-Video";
            nice = -3;
          }
          # Plex Plugin Host - normal priority
          {
            name = "Plex Script Hos";
            nice = 0;
          }
        ];
      };
    };
}
