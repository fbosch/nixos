_: {
  flake.modules.nixos."services/freshrss" =
    { config
    , lib
    , ...
    }:
    let
      cfg = config.services.freshrss;
      synologyDomain = lib.attrByPath [
        "flake"
        "meta"
        "synology"
        "domain"
      ] "corvus-corax.synology.me"
        config;
      # Use string concatenation to avoid Nix parsing // as comment
      slash = "/";
      fullcontentStart = "<!-- FULLCONTENT start " + slash + slash + "-->";
      fullcontentEnd = "<!-- FULLCONTENT end " + slash + slash + "-->";
    in
    {
      options.services.freshrss = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 8084;
          description = "Port for FreshRSS web interface (nginx reverse proxy).";
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Open firewall port for FreshRSS web interface.";
        };

        domain = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "freshrss.example.com";
          description = "Domain for FreshRSS. If null, uses synology domain from flake.meta.";
        };

        enableCaching = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable nginx FastCGI caching for RSS feeds and API responses.";
        };

        cacheTime = lib.mkOption {
          type = lib.types.str;
          default = "5m";
          description = "How long to cache RSS feeds and API responses (e.g., '5m', '1h').";
        };
      };

      config = lib.mkMerge [
        # SOPS secret configuration (only if sops is available)
        (lib.mkIf (config ? sops) {
          sops.secrets.freshrss-admin-password = {
            mode = "0440";
            owner = "freshrss";
            group = "freshrss";
            sopsFile = ../../secrets/containers.yaml;
          };
        })

        # Main FreshRSS configuration
        {
          services.freshrss = {
            enable = lib.mkDefault true;
            defaultUser = lib.mkDefault "admin";
            language = lib.mkDefault "en";
            database.type = lib.mkDefault "sqlite";
            authType = lib.mkDefault "form";
            api.enable = lib.mkDefault true;
            baseUrl = lib.mkDefault "https://${
              if cfg.domain != null then cfg.domain else "freshrss.${synologyDomain}"
            }";
            passwordFile = lib.mkIf (config ? sops) config.sops.secrets.freshrss-admin-password.path;
          };

          networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

          # Fix systemd service ordering - ensure SOPS secrets are installed before FreshRSS config
          systemd.services.freshrss-config = lib.mkIf (config ? sops) {
            after = [ "sops-install-secrets.service" ];
            wants = [ "sops-install-secrets.service" ];
          };
        }

        # Override the default nginx virtualHost to use custom port and add performance optimizations
        {
          services = {
            nginx = {
              virtualHosts.${config.services.freshrss.virtualHost} = {
                listen = [
                  {
                    addr = "0.0.0.0";
                    inherit (cfg) port;
                  }
                ];

                locations = lib.mkMerge [
                  # Static files - aggressive caching
                  {
                    "~ ^/(themes|scripts)/.*\\.(css|js|png|jpg|jpeg|gif|svg|ico|woff|woff2|ttf|eot)$".extraConfig = ''
                      expires 1y;
                      add_header Cache-Control "public, immutable";
                      access_log off;
                    '';
                  }

                  # Override PHP location with caching for RSS/API endpoints
                  (lib.mkIf cfg.enableCaching {
                    "~ ^.+?\\.php(/.*)?$".extraConfig = lib.mkForce ''
                        # FastCGI cache configuration
                        fastcgi_cache_key "$scheme$request_method$host$request_uri";

                        # CRITICAL: Ignore cache-busting headers from FreshRSS
                        # FreshRSS sends "Cache-Control: private, must-revalidate, max-age=0"
                        # which prevents nginx from caching. We override this to cache anyway.
                        fastcgi_ignore_headers Cache-Control Expires Set-Cookie;

                        # Cache RSS feeds and API
                        set $skip_cache 0;
                        if ($request_uri !~ "/(i/\?|api/)") {
                          set $skip_cache 1;
                        }
                        if ($http_authorization != "") {
                          set $skip_cache 1;
                        }
                        if ($http_pragma = "no-cache") {
                          set $skip_cache 1;
                        }

                        fastcgi_cache freshrss_cache;
                        fastcgi_cache_valid 200 ${cfg.cacheTime};
                        fastcgi_cache_bypass $skip_cache;
                        fastcgi_no_cache $skip_cache;
                        fastcgi_cache_use_stale error timeout invalid_header updating http_500;
                        add_header X-Cache-Status $upstream_cache_status;

                        # FreshRSS full-content markers leak into some RSS consumers.
                        # Strip only the internal marker comments while keeping content.
                        sub_filter_once off;
                        sub_filter_types application/rss+xml text/xml application/xml text/html;
                        sub_filter "${fullcontentStart}" "";
                        sub_filter "${fullcontentEnd}" "";

                      # Original FreshRSS FastCGI config
                      fastcgi_pass unix:${config.services.phpfpm.pools.${config.services.freshrss.pool}.socket};
                      fastcgi_split_path_info ^(.+\.php)(/.*)$;
                      set $path_info $fastcgi_path_info;
                      fastcgi_param PATH_INFO $path_info;
                      include ${config.services.nginx.package}/conf/fastcgi_params;
                      include ${config.services.nginx.package}/conf/fastcgi.conf;
                    '';
                  })
                ];
              };

              # FastCGI cache configuration
              commonHttpConfig = lib.mkIf cfg.enableCaching ''
                fastcgi_cache_path /var/cache/nginx/freshrss levels=1:2 keys_zone=freshrss_cache:10m max_size=100m inactive=60m use_temp_path=off;
              '';
            };

            # PHP-FPM performance tuning
            phpfpm.pools.${config.services.freshrss.pool} = {
              settings = {
                # Increase process limits for better concurrency
                "pm.max_children" = lib.mkDefault 20;
                "pm.start_servers" = lib.mkDefault 4;
                "pm.min_spare_servers" = lib.mkDefault 2;
                "pm.max_spare_servers" = lib.mkDefault 6;

                # Enable OPcache for better PHP performance
                "php_admin_value[opcache.enable]" = "1";
                "php_admin_value[opcache.memory_consumption]" = "128";
                "php_admin_value[opcache.interned_strings_buffer]" = "8";
                "php_admin_value[opcache.max_accelerated_files]" = "4000";
                "php_admin_value[opcache.validate_timestamps]" = "0";
                "php_admin_value[opcache.revalidate_freq]" = "0";
              };
            };
          };

          # Create cache directory
          systemd.tmpfiles.rules = lib.mkIf cfg.enableCaching [
            "d /var/cache/nginx/freshrss 0755 nginx nginx -"
          ];
        }
      ];
    };
}
