_:
{
  flake.modules.nixos."services/home-assistant" =
    { config
    , lib
    , ...
    }:
    let
      cfg = config.services.home-assistant;
    in
    {
      options.services.home-assistant = {
        nginx = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable nginx reverse proxy with caching for Home Assistant";
          };

          port = lib.mkOption {
            type = lib.types.port;
            default = 8124;
            description = "Port for nginx reverse proxy (use different from Home Assistant's 8123)";
          };

          backendPort = lib.mkOption {
            type = lib.types.port;
            default = 8123;
            description = "Backend Home Assistant port";
          };

          cacheSize = lib.mkOption {
            type = lib.types.str;
            default = "1g";
            description = "Maximum size of nginx cache for Home Assistant static content";
          };

          cacheTTL = lib.mkOption {
            type = lib.types.str;
            default = "24h";
            description = "Time to cache frontend assets (HTML, CSS, JS)";
          };
        };
      };

      config = {
        services = {
          home-assistant = {
            enable = lib.mkDefault true;

            # Use a more recent version from unstable if needed
            # package = pkgs.unstable.home-assistant;

            # Configuration directory
            # This will store all Home Assistant data, configs, and databases
            configDir = "/var/lib/hass";

            # Extra packages to make available to Home Assistant
            # Add integrations and dependencies here as needed
            extraPackages =
              python3Packages: with python3Packages; [
                # Common integrations
                aiohue # Philips Hue
                aiohomekit # HomeKit Controller
                pyatv # Apple TV
                pychromecast # Chromecast / Google Cast
                # pymetno  # Met.no weather
                # gTTS  # Google Text-to-Speech
                # psycopg2  # PostgreSQL support
                isal
                zlib-ng
              ];

            # Extra components to enable
            # This pre-loads integrations for faster startup
            extraComponents = [
              "default_config" # Include default integrations
              "met" # Weather
              "esphome" # ESPHome integration
              "mqtt" # MQTT support
              "nest" # Google Nest integration
              "samsungtv" # Samsung Smart TV
              "cast" # Chromecast / Google Cast
              "wake_on_lan" # Wake-on-LAN support (useful for Samsung TV)
              "apple_tv" # Apple TV
              "tuya" # Tuya/SmartLife (for Nedis SmartLife devices)
              "pi_hole"
              "synology_dsm"
              # Add more as needed:
              # "hue"
              # "homekit"
              # "mobile_app"
              # "zha"  # Zigbee Home Automation
            ];

            # Configuration.yaml content
            # For complex configs, consider using configDir and managing files separately
            config = {
              default_config = { };

              http = {
                server_port = cfg.nginx.backendPort;
                use_x_forwarded_for = true;
                trusted_proxies = [
                  "127.0.0.1"
                  "192.168.1.2"
                  "192.168.1.0/24"
                ];
              };

              homeassistant = {
                name = "Home";
                # Set your location for weather, sunrise/sunset, etc.
                # latitude = 52.520008;
                # longitude = 13.404954;
                # elevation = 34;
                # unit_system = "metric";
                # time_zone = "Europe/Berlin";
              };

              # Enable frontend
              frontend = { };

              # Enable automation UI
              automation = [ ];
              script = [ ];
              scene = [ ];
            };
          };

          # Optional: Enable mDNS for .local domain discovery
          avahi = {
            enable = true;
            nssmdns4 = true;
            publish = {
              enable = true;
              addresses = true;
              domain = true;
              workstation = true;
            };
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
              proxy_cache_path /var/cache/nginx/home-assistant
                levels=1:2
                keys_zone=home_assistant_cache:10m
                max_size=${cfg.nginx.cacheSize}
                inactive=${cfg.nginx.cacheTTL}
                use_temp_path=off;
            '';

            upstreams.home-assistant = {
              servers."127.0.0.1:${toString cfg.nginx.backendPort}" = { };
            };

            virtualHosts."home-assistant-proxy" = {
              listen = [
                {
                  addr = "0.0.0.0";
                  inherit (cfg.nginx) port;
                }
              ];

              locations = {
                # Cache static frontend bundles (JS/CSS) - Long TTL
                "~ ^/(frontend_latest|frontend_es5|static)/" = {
                  proxyPass = "http://home-assistant";
                  extraConfig = ''
                    proxy_cache home_assistant_cache;
                    proxy_cache_valid 200 7d;
                    proxy_cache_valid 404 1h;
                    proxy_cache_key "$scheme$request_method$host$request_uri";
                    proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
                    proxy_cache_background_update on;
                    proxy_cache_lock on;
                    add_header X-Cache-Status $upstream_cache_status;
                    add_header Cache-Control "public, max-age=604800, immutable";

                    # Enable buffering for caching
                    proxy_buffering on;
                    proxy_buffer_size 16k;
                    proxy_buffers 32 8k;
                    proxy_busy_buffers_size 64k;

                    # Headers
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto $scheme;
                  '';
                };

                # Cache icons, fonts, and images - Long TTL
                "~ ^/(local|hacsfiles)/" = {
                  proxyPass = "http://home-assistant";
                  extraConfig = ''
                    proxy_cache home_assistant_cache;
                    proxy_cache_valid 200 7d;
                    proxy_cache_valid 404 1h;
                    proxy_cache_key "$scheme$request_method$host$request_uri";
                    proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
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

                # Cache service worker and manifest - Medium TTL
                "~ ^/(service_worker.js|manifest.json)" = {
                  proxyPass = "http://home-assistant";
                  extraConfig = ''
                    proxy_cache home_assistant_cache;
                    proxy_cache_valid 200 1h;
                    proxy_cache_key "$scheme$request_method$host$request_uri";
                    add_header X-Cache-Status $upstream_cache_status;
                    add_header Cache-Control "public, max-age=3600";

                    # Enable buffering for caching
                    proxy_buffering on;

                    # Headers
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto $scheme;
                  '';
                };

                # WebSocket - NO caching, special handling
                "/api/websocket" = {
                  proxyPass = "http://home-assistant";
                  extraConfig = ''
                    # Disable caching for WebSocket
                    proxy_no_cache 1;
                    proxy_cache_bypass 1;

                    # Disable buffering for WebSocket
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

                    # Timeouts for long-running WebSocket connections
                    proxy_read_timeout 86400s;
                    proxy_send_timeout 86400s;
                  '';
                };

                # API endpoints - NO caching (real-time data)
                "~ ^/api/" = {
                  proxyPass = "http://home-assistant";
                  extraConfig = ''
                    # Disable caching for API
                    proxy_no_cache 1;
                    proxy_cache_bypass 1;

                    # Disable buffering for API
                    proxy_buffering off;

                    # Headers
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto $scheme;

                    add_header X-Cache-Status "BYPASS";
                  '';
                };

                # Auth endpoints - NO caching
                "~ ^/auth/" = {
                  proxyPass = "http://home-assistant";
                  extraConfig = ''
                    # Disable caching for auth
                    proxy_no_cache 1;
                    proxy_cache_bypass 1;

                    # Disable buffering for auth
                    proxy_buffering off;

                    # Headers
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto $scheme;

                    add_header X-Cache-Status "BYPASS";
                  '';
                };

                # Root and other paths - Cache main UI
                "/" = {
                  proxyPass = "http://home-assistant";
                  extraConfig = ''
                    proxy_cache home_assistant_cache;
                    proxy_cache_valid 200 ${cfg.nginx.cacheTTL};
                    proxy_cache_key "$scheme$request_method$host$request_uri";
                    proxy_cache_bypass $http_upgrade;
                    add_header X-Cache-Status $upstream_cache_status;

                    # Ignore Home Assistant's cache control headers and force caching
                    proxy_ignore_headers Cache-Control Expires Set-Cookie;
                    proxy_hide_header Cache-Control;
                    add_header Cache-Control "public, max-age=86400";

                    # Enable buffering for caching
                    proxy_buffering on;
                    proxy_buffer_size 16k;
                    proxy_buffers 16 8k;
                    proxy_busy_buffers_size 32k;

                    # Headers
                    proxy_set_header Host $host;
                    proxy_set_header X-Real-IP $remote_addr;
                    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                    proxy_set_header X-Forwarded-Proto $scheme;
                  '';
                };
              };
            };
          };
        };

        # Open firewall for Home Assistant web interface and nginx proxy
        networking.firewall.allowedTCPPorts = [
          cfg.nginx.backendPort
        ]
        ++ lib.optional cfg.nginx.enable cfg.nginx.port;

        # Ensure the service starts after network is ready
        systemd.services.home-assistant = {
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
        };

        # Create cache directory
        systemd.tmpfiles.rules = lib.mkIf cfg.nginx.enable [
          "d /var/cache/nginx/home-assistant 0750 nginx nginx -"
        ];
      };
    };
}
