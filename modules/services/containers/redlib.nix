_: {
  flake.modules.nixos."services/containers/redlib" =
    { config
    , lib
    , ...
    }:
    let
      cfg = config.services.redlib-container;
    in
    {
      options.services.redlib-container = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 8282;
          description = "Port for Redlib web interface";
        };

        theme = lib.mkOption {
          type = lib.types.str;
          default = "system";
          description = ''
            Default theme for Redlib.
            Options: system, light, dark, black, dracula, nord, laserwave, violet, gold, rosebox, gruvboxdark, gruvboxlight
          '';
        };

        useHls = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Use HTTP Live Streaming for videos (reduces memory usage)";
        };

        memory = lib.mkOption {
          type = lib.types.str;
          default = "1g";
          description = "Memory limit for the container (e.g., 512m, 1g, 2g)";
        };

        cpuQuota = lib.mkOption {
          type = lib.types.str;
          default = "400%";
          description = "CPU quota for the container (e.g., 200% = 2 cores, 400% = 4 cores)";
        };

        pidsLimit = lib.mkOption {
          type = lib.types.int;
          default = 512;
          description = "Maximum number of PIDs (processes/threads) the container can create";
        };

        nofileLimit = lib.mkOption {
          type = lib.types.str;
          default = "4096:8192";
          description = "File descriptor limits (soft:hard)";
        };

        nginx = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable nginx reverse proxy with caching for Redlib.";
          };

          port = lib.mkOption {
            type = lib.types.port;
            default = 8283;
            description = "Port for nginx reverse proxy (separate from container port).";
          };

          cacheSize = lib.mkOption {
            type = lib.types.str;
            default = "500m";
            description = "Maximum size of nginx cache for Redlib static content.";
          };

          cacheTTL = lib.mkOption {
            type = lib.types.str;
            default = "1h";
            description = "Time to cache static content (CSS/JS).";
          };

          imageCacheTTL = lib.mkOption {
            type = lib.types.str;
            default = "2h";
            description = "Time to cache images and media.";
          };

          enableHttp2 = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable HTTP/2 support for better performance.";
          };
        };
      };

      config = {
        services.containerPorts = lib.mkAfter [
          {
            service = "redlib-container";
            tcpPorts = [ config.services.redlib-container.port ];
          }
        ];

        environment.etc."containers/systemd/redlib.container".text = ''
          [Unit]
          After=network-online.target
          Wants=network-online.target

          [Container]
          ContainerName=redlib
          Image=quay.io/redlib/redlib:latest
          PublishPort=${toString config.services.redlib-container.port}:8080
          Environment=REDLIB_DEFAULT_THEME=${config.services.redlib-container.theme}
          Environment=REDLIB_DEFAULT_USE_HLS=${
            if config.services.redlib-container.useHls then "on" else "off"
          }
          Memory=${config.services.redlib-container.memory}
          PidsLimit=${toString config.services.redlib-container.pidsLimit}
          Ulimit=nofile=${config.services.redlib-container.nofileLimit}
          LogDriver=journald
          LogOpt=tag=redlib

          [Service]
          CPUQuota=${config.services.redlib-container.cpuQuota}
          Restart=always
          RestartSec=10
          TimeoutStartSec=300

          [Install]
          WantedBy=multi-user.target
        '';

        # Open firewall for Redlib web interface
        networking.firewall.allowedTCPPorts = [ cfg.port ] ++ lib.optional cfg.nginx.enable cfg.nginx.port;

        # Nginx reverse proxy with caching
        services.nginx = lib.mkIf cfg.nginx.enable {
          enable = true;

          # Recommended settings for reverse proxy
          recommendedProxySettings = true;
          recommendedOptimisation = true;
          recommendedGzipSettings = true;
          recommendedTlsSettings = true;

          # Performance tuning
          eventsConfig = ''
            worker_connections 2048;
            use epoll;
            multi_accept on;
          '';

          # Cache path configuration + connection pooling
          appendHttpConfig = ''
            proxy_cache_path /var/cache/nginx/redlib
              levels=1:2
              keys_zone=redlib_cache:10m
              max_size=${cfg.nginx.cacheSize}
              inactive=${cfg.nginx.cacheTTL}
              use_temp_path=off;

            # Connection pooling to Redlib backend
            upstream redlib_backend {
              server 127.0.0.1:${toString cfg.port};
              keepalive 32;
              keepalive_requests 100;
              keepalive_timeout 60s;
            }

            # Enable HTTP/2 push for static assets
            http2_push_preload on;
          '';

          upstreams.redlib = {
            servers."127.0.0.1:${toString cfg.port}" = { };
          };

          virtualHosts."redlib-proxy" = {
            listen = [
              {
                addr = "0.0.0.0";
                port = cfg.nginx.port;
              }
            ];

            # Enable HTTP/2
            http2 = cfg.nginx.enableHttp2;

            locations = {
              # Cache static assets (CSS, JS, images)
              "~ ^/(style\\.css|static/)" = {
                proxyPass = "http://redlib_backend";
                extraConfig = ''
                  proxy_cache redlib_cache;
                  proxy_cache_valid 200 ${cfg.nginx.cacheTTL};
                  proxy_cache_key "$scheme$request_method$host$request_uri";
                  add_header X-Cache-Status $upstream_cache_status;
                  add_header Cache-Control "public, max-age=3600";

                  # Enable buffering for caching
                  proxy_buffering on;

                  # Connection pooling
                  proxy_http_version 1.1;
                  proxy_set_header Connection "";

                  # Headers
                  proxy_set_header Host $host;
                  proxy_set_header X-Real-IP $remote_addr;
                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                  proxy_set_header X-Forwarded-Proto $scheme;
                '';
              };

              # Cache Reddit media proxied through Redlib (aggressive caching)
              "~ ^/(vid|img|thumb|hls|emoji)" = {
                proxyPass = "http://redlib_backend";
                extraConfig = ''
                  proxy_cache redlib_cache;
                  proxy_cache_valid 200 ${cfg.nginx.imageCacheTTL};
                  proxy_cache_key "$scheme$request_method$host$request_uri";
                  add_header X-Cache-Status $upstream_cache_status;
                  add_header Cache-Control "public, max-age=7200";

                  # Enable buffering for caching
                  proxy_buffering on;
                  proxy_buffer_size 16k;
                  proxy_buffers 32 16k;

                  # Connection pooling
                  proxy_http_version 1.1;
                  proxy_set_header Connection "";

                  # Headers
                  proxy_set_header Host $host;
                  proxy_set_header X-Real-IP $remote_addr;
                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                  proxy_set_header X-Forwarded-Proto $scheme;
                '';
              };

              # Cache user profiles and subreddit info briefly
              "~ ^/(r/[^/]+/(about|sidebar)|u/[^/]+/about)" = {
                proxyPass = "http://redlib_backend";
                extraConfig = ''
                  proxy_cache redlib_cache;
                  proxy_cache_valid 200 10m;
                  proxy_cache_key "$scheme$request_method$host$request_uri";
                  add_header X-Cache-Status $upstream_cache_status;

                  # Enable buffering for caching
                  proxy_buffering on;

                  # Connection pooling
                  proxy_http_version 1.1;
                  proxy_set_header Connection "";

                  # Headers
                  proxy_set_header Host $host;
                  proxy_set_header X-Real-IP $remote_addr;
                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                  proxy_set_header X-Forwarded-Proto $scheme;
                '';
              };

              # Don't cache dynamic content (subreddit pages, user pages, etc.)
              "/" = {
                proxyPass = "http://redlib_backend";
                extraConfig = ''
                  # Disable caching for dynamic content
                  proxy_no_cache 1;
                  proxy_cache_bypass 1;

                  # Disable buffering for dynamic responses
                  proxy_buffering off;

                  # Connection pooling
                  proxy_http_version 1.1;
                  proxy_set_header Connection "";

                  # Headers
                  proxy_set_header Host $host;
                  proxy_set_header X-Real-IP $remote_addr;
                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                  proxy_set_header X-Forwarded-Proto $scheme;

                  # Timeouts
                  proxy_read_timeout 60s;
                  proxy_send_timeout 60s;
                '';
              };
            };
          };
        };

        systemd.tmpfiles.rules = lib.mkIf cfg.nginx.enable [
          "d /var/cache/nginx/redlib 0750 nginx nginx -"
        ];
      };
    };
}
