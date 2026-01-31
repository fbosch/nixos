_: {
  flake.modules.nixos."services/containers/helium" =
    { config
    , lib
    , pkgs
    , ...
    }:
    {
      options.services.helium-services-container = {
        hostname = lib.mkOption {
          type = lib.types.str;
          default = "services.helium.local";
          description = "Hostname for the Helium services";
        };

        httpPort = lib.mkOption {
          type = lib.types.nullOr lib.types.port;
          default = null;
          description = "HTTP port for nginx";
        };

        hmacSecret = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "HMAC secret for signing proxied CRX downloads";
        };

        hmacSecretFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Path to file containing HMAC secret";
        };

        proxyBaseUrl = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Base URL for extension proxy";
          example = "https://services.helium.local/ext";
        };

        uboProxyBaseUrl = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Base URL for uBlock Origin proxy";
          example = "https://services.helium.local/ubo";
        };

        useOriginalUboAssets = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Use original uBlock Origin assets instead of Helium-specific filters";
        };

        uboAssetsJsonUrl = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Custom assets.json URL for uBlock Origin";
        };

        uboAssetsJsonSha256 = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "SHA256 hash for custom assets.json";
        };

        dataDir = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/helium-services";
          description = "Directory for persistent data";
        };

        gitRepo = lib.mkOption {
          type = lib.types.str;
          default = "https://github.com/imputnet/helium-services.git";
          description = "Git repository URL for helium-services";
        };

        gitRev = lib.mkOption {
          type = lib.types.str;
          default = "6839e30dc01fe144bfef2730c165ab3e0265d68b";
          description = "Git revision (commit) to fetch";
        };

        gitSha256 = lib.mkOption {
          type = lib.types.str;
          default = "sha256-i785PDqPQee0El9h6zLX8cP+w4Hh/JVBRiiT3byiZ6k=";
          description = "SHA256 for fetched helium-services source";
        };
      };

      config =
        let
          cfg = config.services.helium-services-container;
          envFile = "${cfg.dataDir}/env";
          repoSrc = pkgs.fetchgit {
            url = cfg.gitRepo;
            rev = cfg.gitRev;
            hash = cfg.gitSha256;
          };
          buildDir = "${cfg.dataDir}/repo";
          nginxConf = pkgs.writeText "helium-nginx.conf.j2" ''
            user nginx;
            worker_processes auto;
            daemon off;

            error_log /dev/null crit;
            pid /tmp/nginx.pid;

            events {
                worker_connections 1024;
            }

            http {
                include /etc/nginx/mime.types;
                default_type application/octet-stream;

                access_log off;
                error_log /dev/null crit;

                server_tokens off;
                client_max_body_size 64k;

                sendfile on;
                tcp_nopush on;

                gzip on;
                gzip_vary on;
                gzip_static on;
                gzip_types text/plain application/json "application/xml; charset=utf-8" "application/json; charset=utf-8";

                keepalive_timeout 20s;

                client_body_temp_path /tmp/client_temp;
                proxy_temp_path       /tmp/proxy_temp_path;
                fastcgi_temp_path     /tmp/fastcgi_temp;
                uwsgi_temp_path       /tmp/uwsgi_temp;
                scgi_temp_path        /tmp/scgi_temp;
                proxy_cache_path      /tmp/ubo_cache levels=1:2 keys_zone=ubo:512k;

                upstream exts {
                    server ext_proxy:8000;
                    server ext_proxy_backup:8000 backup;
                }

                server {
                    listen [::]:80 ipv6only=off default_server;
                    server_name {{ services_hostname }};

                    location = / {
                        return 302 https://helium.computer;
                    }

                    location = /robots.txt {
                        add_header Content-Type text/plain;
                        return 200 "User-agent: *\nDisallow: /\n";
                    }

                    location = /bangs.json {
                        add_header Cache-Control "public, max-age=86400, stale-if-error=604800";
                        add_header Access-Control-Allow-Origin *;
                        root /dev/shm/bangs;
                    }

                    location /updates/mac {
                        proxy_pass https://updates.helium.computer/mac;
                    }

                    location /dict {
                        gzip_static always;
                        root /dev/shm/dictionaries;

                        autoindex on;
                        sub_filter ".gz" "";
                        sub_filter_once off;
                    }

                    location /ext/ {
                        proxy_pass http://exts/;
                    }

                    location /com {
                        proxy_pass http://exts/com;
                    }

                    location /ubo/ {
                        proxy_pass http://ubo_proxy:8000/;
                        proxy_pass_request_body off;
                    }
                }
            }
          '';
          nginxEntrypoint = pkgs.writeText "helium-nginx-entrypoint.sh" ''
            #!/bin/sh
            ./refresh-bangs.sh &
            ./refresh-dicts.sh &

            echo -en "waiting for all hosts to come up";
            while ! nginx -t >/dev/null 2>/dev/null; do
                echo -en .
                sleep 0.1
            done
            echo " ready!"

            nginx
          '';
        in
        {
          services.containerPorts = lib.mkAfter [
            {
              service = "helium-services-container";
              tcpPorts = lib.optional (cfg.httpPort != null) cfg.httpPort;
            }
          ];

          systemd.tmpfiles.rules = [
            "d ${cfg.dataDir} 0755 root root -"
            "d ${buildDir} 0755 root root -"
          ];

          systemd.services.helium-services-build = {
            description = "Build helium-services container images";
            wantedBy = [ "multi-user.target" ];
            after = [
              "network-online.target"
              "podman.service"
            ];
            wants = [ "network-online.target" ];
            requires = [
              "podman.service"
            ];

            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              TimeoutStartSec = "600";
            };

            script = ''
              ${pkgs.coreutils}/bin/rm -rf "${buildDir}"
              ${pkgs.coreutils}/bin/cp -R ${repoSrc} "${buildDir}"
              cd "${buildDir}"

              ${pkgs.coreutils}/bin/install -m 0644 ${nginxConf} "${buildDir}/svc/nginx/nginx.conf.j2"
              ${pkgs.coreutils}/bin/install -m 0755 ${nginxEntrypoint} "${buildDir}/svc/nginx/entrypoint.sh"

              ${pkgs.podman}/bin/podman build \
                -t helium-nginx:latest \
                -f ./svc/nginx/Dockerfile \
                --build-arg SERVICES_HOSTNAME=${lib.escapeShellArg cfg.hostname} \
                ./svc

              ${pkgs.podman}/bin/podman build \
                -t helium-ubo-proxy:latest \
                -f ./svc/ubo/Dockerfile \
                ./svc/ubo

              ${pkgs.podman}/bin/podman build \
                -t helium-ext-proxy:latest \
                -f ./svc/extension-proxy/Dockerfile \
                ./svc/extension-proxy
            '';
          };

          systemd.services.helium-services-env = {
            description = "Write helium-services environment file";
            wantedBy = [ "multi-user.target" ];
            before = [
              "container-helium-ubo-proxy.service"
              "container-helium-ext-proxy.service"
              "container-helium-ext-proxy-backup.service"
            ];

            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };

            script = ''
              install -m 600 /dev/null "${envFile}"

              HMAC_SECRET_VALUE=${lib.escapeShellArg cfg.hmacSecret}
              ${lib.optionalString (cfg.hmacSecretFile != null) ''
                HMAC_SECRET_VALUE="$(cat ${lib.escapeShellArg cfg.hmacSecretFile})"
              ''}

              printf '%s\n' "HMAC_SECRET=$HMAC_SECRET_VALUE" >> "${envFile}"
              printf '%s\n' "SERVICES_HOSTNAME=${cfg.hostname}" >> "${envFile}"
              printf '%s\n' "PROXY_BASE_URL=${cfg.proxyBaseUrl}" >> "${envFile}"
              printf '%s\n' "UBO_PROXY_BASE_URL=${cfg.uboProxyBaseUrl}" >> "${envFile}"
              printf '%s\n' "UBO_USE_ORIGINAL_UBLOCK_ASSETS=${
                if cfg.useOriginalUboAssets then "1" else "0"
              }" >> "${envFile}"
              ${lib.optionalString (cfg.uboAssetsJsonUrl != null) ''
                printf '%s\n' "UBO_ASSETS_JSON_URL=${cfg.uboAssetsJsonUrl}" >> "${envFile}"
              ''}
              ${lib.optionalString (cfg.uboAssetsJsonSha256 != null) ''
                printf '%s\n' "UBO_ASSETS_JSON_SHA256=${cfg.uboAssetsJsonSha256}" >> "${envFile}"
              ''}
            '';
          };

          environment.etc."containers/systemd/helium-ubo-proxy.container".text = ''
            [Unit]
            After=network-online.target helium-services-build.service helium-services-env.service
            Wants=network-online.target
            Requires=helium-services-build.service helium-services-env.service

            [Container]
            ContainerName=ubo_proxy
            Image=helium-ubo-proxy:latest
            ReadOnly=true
            Network=helium.network
            EnvironmentFile=${envFile}

            [Service]
            Restart=always
            RestartSec=10

            [Install]
            WantedBy=multi-user.target
          '';

          environment.etc."containers/systemd/helium-ext-proxy.container".text = ''
            [Unit]
            After=network-online.target helium-services-build.service helium-services-env.service
            Wants=network-online.target
            Requires=helium-services-build.service helium-services-env.service

            [Container]
            ContainerName=ext_proxy
            Image=helium-ext-proxy:latest
            ReadOnly=true
            Network=helium.network
            EnvironmentFile=${envFile}

            [Service]
            Restart=always
            RestartSec=10

            [Install]
            WantedBy=multi-user.target
          '';

          environment.etc."containers/systemd/helium-ext-proxy-backup.container".text = ''
            [Unit]
            After=network-online.target helium-services-build.service helium-services-env.service
            Wants=network-online.target
            Requires=helium-services-build.service helium-services-env.service

            [Container]
            ContainerName=ext_proxy_backup
            Image=helium-ext-proxy:latest
            ReadOnly=true
            Network=helium.network
            EnvironmentFile=${envFile}

            [Service]
            Restart=always
            RestartSec=10

            [Install]
            WantedBy=multi-user.target
          '';

          environment.etc."containers/systemd/helium.network".text = ''
            [Network]
            NetworkName=helium
          '';

          environment.etc."containers/systemd/helium-nginx.container".text = ''
            [Unit]
            After=network-online.target helium-services-build.service helium-services-env.service
            Wants=network-online.target
            Requires=helium-services-build.service helium-services-env.service

            [Container]
            ContainerName=nginx
            Image=helium-nginx:latest
            ReadOnly=true
            RunInit=true
            Network=helium.network
            ${lib.optionalString (cfg.httpPort != null) "PublishPort=${toString cfg.httpPort}:80/tcp"}
            Tmpfs=/tmp:rw,size=512M
            ShmSize=512m
            EnvironmentFile=${envFile}
            LogDriver=journald
            LogOpt=tag=helium-nginx

            [Service]
            Restart=always
            RestartSec=10

            [Install]
            WantedBy=multi-user.target
          '';

          networking.firewall.allowedTCPPorts = [
          ]
          ++ lib.optional (cfg.httpPort != null) cfg.httpPort;
        };
    };
}
