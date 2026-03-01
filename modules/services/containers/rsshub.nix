_: {
  flake.modules.nixos."services/containers/rsshub" =
    { config
    , lib
    , ...
    }:
    let
      cfg = config.services.rsshub-container;
    in
    {
      options.services.rsshub-container = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 1200;
          description = "Port for RSSHub web interface";
        };

        imageTag = lib.mkOption {
          type = lib.types.str;
          default = "latest";
          description = "RSSHub container image tag";
        };

        redisImageTag = lib.mkOption {
          type = lib.types.str;
          default = "7-alpine";
          description = "Redis container image tag used for RSSHub cache";
        };

        cacheType = lib.mkOption {
          type = lib.types.enum [
            "memory"
            "redis"
          ];
          default = "redis";
          description = "RSSHub cache backend";
        };
      };

      config = {
        services.containerPorts = lib.mkAfter [
          {
            service = "rsshub-container";
            tcpPorts = [ cfg.port ];
          }
        ];

        environment.etc = {
          "containers/systemd/rsshub.container".text = ''
            [Unit]
            Description=RSSHub feed service
            After=network-online.target rsshub-network.service rsshub-redis.service
            Wants=network-online.target
            Requires=rsshub-network.service rsshub-redis.service

            [Container]
            ContainerName=rsshub
            Image=docker.io/diygod/rsshub:${cfg.imageTag}
            Network=rsshub.network
            PublishPort=${toString cfg.port}:1200
            Environment=NODE_ENV=production
            Environment=CACHE_TYPE=${cfg.cacheType}
            Environment=REDIS_URL=redis://rsshub-redis:6379/
            LogDriver=journald
            LogOpt=tag=rsshub

            [Service]
            Restart=always
            RestartSec=10
            TimeoutStartSec=120

            [Install]
            WantedBy=multi-user.target
          '';

          "containers/systemd/rsshub-redis.container".text = ''
            [Unit]
            Description=RSSHub Redis cache
            After=network-online.target rsshub-network.service
            Wants=network-online.target
            Requires=rsshub-network.service

            [Container]
            ContainerName=rsshub-redis
            Image=docker.io/library/redis:${cfg.redisImageTag}
            Network=rsshub.network
            Volume=rsshub-redis-data.volume:/data
            LogDriver=journald
            LogOpt=tag=rsshub-redis

            [Service]
            Restart=always
            RestartSec=10
            TimeoutStartSec=60

            [Install]
            WantedBy=multi-user.target
          '';

          "containers/systemd/rsshub-redis-data.volume".text = ''
            [Volume]
            VolumeName=rsshub-redis-data
          '';

          "containers/systemd/rsshub.network".text = ''
            [Network]
            NetworkName=rsshub
          '';
        };

        networking.firewall.allowedTCPPorts = [ cfg.port ];
      };
    };
}
