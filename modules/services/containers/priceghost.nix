{ config, ... }:
let
  inherit (config.flake.lib) sopsHelpers;
  containersFile = ../../../secrets/containers.yaml;
in
{
  # PriceGhost - Self-hosted price tracking application
  # https://github.com/clucraft/PriceGhost
  #
  # SETUP:
  # 1. Add secrets to secrets/containers.yaml:
  #    - priceghost-postgres-password
  #    - priceghost-jwt-secret
  # 2. Access the web UI at http://<host>:8089

  flake.modules.nixos."services/containers/priceghost" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      cfg = config.services.priceghost-container;
      priceghostRev = "33b944588d5b5e9689909858da1b9e92c369bd3f";
      priceghostSource = pkgs.fetchFromGitHub {
        owner = "clucraft";
        repo = "PriceGhost";
        rev = priceghostRev;
        hash = "sha256-Qi+RP1iEtluxIff2HKk7o9CBAVWWUJ5YBSUwg5FdOU0=";
      };
      priceghostDkkPatch = ./priceghost-dkk.patch;

      buildImagesScript = pkgs.writeShellScriptBin "build-priceghost-images" ''
        set -euo pipefail

        if [ "$(${pkgs.coreutils}/bin/id -u)" -ne 0 ]; then
          echo "This command must run as root so systemd can use the images."
          echo "Run: sudo build-priceghost-images"
          exit 1
        fi

        temp_dir="$(${pkgs.coreutils}/bin/mktemp -d)"
        trap 'rm -rf "$temp_dir"' EXIT

        echo "==> Copying PriceGhost source..."
        ${pkgs.coreutils}/bin/cp -a ${priceghostSource}/. "$temp_dir"
        ${pkgs.coreutils}/bin/chmod -R u+w "$temp_dir"

        cd "$temp_dir"

        echo "==> Patching DKK support..."
        ${pkgs.patch}/bin/patch -p1 < ${priceghostDkkPatch}

        echo "==> Building PriceGhost backend image..."
        ${pkgs.podman}/bin/podman build --format docker \
          -t localhost/priceghost-backend:${cfg.backendImageTag} \
          -f backend/Dockerfile \
          backend/

        echo "==> Building PriceGhost frontend image..."
        ${pkgs.podman}/bin/podman build --format docker \
          -t localhost/priceghost-frontend:${cfg.frontendImageTag} \
          -f frontend/Dockerfile \
          frontend/
      '';

      backendEnvScript = pkgs.writeShellScript "priceghost-backend-env" ''
        set -euo pipefail

        ${pkgs.python3}/bin/python3 - <<'PY'
        from pathlib import Path
        from urllib.parse import quote
        import os

        source = Path("${config.sops.templates."priceghost-env".path}")
        target = Path("${cfg.backendEnvFile}")
        env = {}

        for line in source.read_text().splitlines():
            if not line or line.startswith("#") or "=" not in line:
                continue

            key, value = line.split("=", 1)
            env[key] = value

        target.write_text(
            "JWT_SECRET={jwt}\nDATABASE_URL=postgresql://postgres:{password}@postgres:5432/priceghost\n".format(
                jwt=env["JWT_SECRET"],
                password=quote(env["POSTGRES_PASSWORD"], safe=""),
            )
        )
        os.chmod(target, 0o400)
        PY
      '';
    in
    {
      options.services.priceghost-container = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 8089;
          description = "Port for PriceGhost web interface";
        };

        frontendImageTag = lib.mkOption {
          type = lib.types.str;
          default = "${priceghostRev}-dkk";
          description = "PriceGhost frontend container image tag";
        };

        backendImageTag = lib.mkOption {
          type = lib.types.str;
          default = "${priceghostRev}-dkk";
          description = "PriceGhost backend container image tag";
        };

        buildImages = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Add the build-priceghost-images command for patched local PriceGhost images with DKK currency support";
        };

        postgresImageTag = lib.mkOption {
          type = lib.types.str;
          default = "16-alpine";
          description = "PostgreSQL container image tag";
        };

        postgresMemory = lib.mkOption {
          type = lib.types.str;
          default = "512m";
          description = "Memory limit for the PriceGhost PostgreSQL container";
        };

        backendMemory = lib.mkOption {
          type = lib.types.str;
          default = "1g";
          description = "Memory limit for the PriceGhost backend container";
        };

        frontendMemory = lib.mkOption {
          type = lib.types.str;
          default = "256m";
          description = "Memory limit for the PriceGhost frontend container";
        };

        backendEnvFile = lib.mkOption {
          type = lib.types.str;
          default = "/run/priceghost-backend.env";
          description = "Runtime backend environment file with URL-encoded DATABASE_URL";
        };
      };

      config = {
        environment.systemPackages = lib.mkIf cfg.buildImages [ buildImagesScript ];

        services.exposedPorts = lib.mkAfter [
          {
            service = "priceghost-container";
            tcpPorts = [ cfg.port ];
          }
        ];

        sops = {
          secrets = sopsHelpers.mkSecretsWithOpts containersFile sopsHelpers.rootOnly [
            "priceghost-postgres-password"
            "priceghost-jwt-secret"
          ];

          templates."priceghost-env" = {
            content = ''
              POSTGRES_PASSWORD=${config.sops.placeholder.priceghost-postgres-password}
              JWT_SECRET=${config.sops.placeholder.priceghost-jwt-secret}
            '';
            mode = "0400";
          };
        };

        environment.etc = {
          "priceghost/init.sql".text = ''
            -- PriceGhost Database Schema

            CREATE TABLE IF NOT EXISTS users (
              id SERIAL PRIMARY KEY,
              email VARCHAR(255) UNIQUE NOT NULL,
              password_hash VARCHAR(255) NOT NULL,
              name VARCHAR(255),
              is_admin BOOLEAN DEFAULT false,
              telegram_bot_token VARCHAR(255),
              telegram_chat_id VARCHAR(255),
              discord_webhook_url TEXT,
              created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS system_settings (
              key VARCHAR(255) PRIMARY KEY,
              value TEXT NOT NULL,
              updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );

            INSERT INTO system_settings (key, value) VALUES ('registration_enabled', 'true')
            ON CONFLICT (key) DO NOTHING;

            DO $$
            BEGIN
              IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_name = 'users' AND column_name = 'telegram_bot_token'
              ) THEN
                ALTER TABLE users ADD COLUMN telegram_bot_token VARCHAR(255);
                ALTER TABLE users ADD COLUMN telegram_chat_id VARCHAR(255);
                ALTER TABLE users ADD COLUMN discord_webhook_url TEXT;
              END IF;
            END $$;

            DO $$
            BEGIN
              IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_name = 'users' AND column_name = 'name'
              ) THEN
                ALTER TABLE users ADD COLUMN name VARCHAR(255);
              END IF;
              IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_name = 'users' AND column_name = 'is_admin'
              ) THEN
                ALTER TABLE users ADD COLUMN is_admin BOOLEAN DEFAULT false;
                UPDATE users SET is_admin = true WHERE id = (SELECT MIN(id) FROM users);
              END IF;
            END $$;

            CREATE TABLE IF NOT EXISTS products (
              id SERIAL PRIMARY KEY,
              user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
              url TEXT NOT NULL,
              name VARCHAR(255),
              image_url TEXT,
              refresh_interval INTEGER DEFAULT 3600,
              last_checked TIMESTAMP,
              next_check_at TIMESTAMP,
              stock_status VARCHAR(20) DEFAULT 'unknown',
              price_drop_threshold DECIMAL(10,2),
              target_price DECIMAL(10,2),
              notify_back_in_stock BOOLEAN DEFAULT false,
              created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
              UNIQUE(user_id, url)
            );

            DO $$
            BEGIN
              IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_name = 'products' AND column_name = 'stock_status'
              ) THEN
                ALTER TABLE products ADD COLUMN stock_status VARCHAR(20) DEFAULT 'unknown';
              END IF;
            END $$;

            DO $$
            BEGIN
              IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_name = 'products' AND column_name = 'price_drop_threshold'
              ) THEN
                ALTER TABLE products ADD COLUMN price_drop_threshold DECIMAL(10,2);
                ALTER TABLE products ADD COLUMN notify_back_in_stock BOOLEAN DEFAULT false;
              END IF;
            END $$;

            DO $$
            BEGIN
              IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_name = 'products' AND column_name = 'next_check_at'
              ) THEN
                ALTER TABLE products ADD COLUMN next_check_at TIMESTAMP;
              END IF;
            END $$;

            DO $$
            BEGIN
              IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_name = 'products' AND column_name = 'target_price'
              ) THEN
                ALTER TABLE products ADD COLUMN target_price DECIMAL(10,2);
              END IF;
            END $$;

            CREATE TABLE IF NOT EXISTS price_history (
              id SERIAL PRIMARY KEY,
              product_id INTEGER REFERENCES products(id) ON DELETE CASCADE,
              price DECIMAL(10,2) NOT NULL,
              currency VARCHAR(10) DEFAULT 'USD',
              recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );

            CREATE INDEX IF NOT EXISTS idx_price_history_product_date
            ON price_history(product_id, recorded_at);
          '';

          "containers/systemd/priceghost-postgres.container".text = ''
            [Unit]
            Description=PriceGhost PostgreSQL Database
            After=network-online.target priceghost-network.service
            Wants=network-online.target
            Requires=priceghost-network.service

            [Container]
            ContainerName=priceghost-postgres
            Image=docker.io/library/postgres:${cfg.postgresImageTag}
            Network=priceghost.network
            PodmanArgs=--network-alias=postgres
            Environment=POSTGRES_USER=postgres
            Environment=POSTGRES_DB=priceghost
            EnvironmentFile=${config.sops.templates."priceghost-env".path}
            Volume=priceghost-postgres-data.volume:/var/lib/postgresql/data
            Volume=/etc/priceghost/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
            Memory=${cfg.postgresMemory}
            PidsLimit=500
            LogDriver=journald
            LogOpt=tag=priceghost-postgres

            [Service]
            RestrictAddressFamilies=~AF_ALG
            SystemCallArchitectures=native
            Restart=always
            RestartSec=10
            TimeoutStartSec=120

            [Install]
            WantedBy=multi-user.target
          '';

          "containers/systemd/priceghost-backend.container".text = ''
            [Unit]
            Description=PriceGhost Backend API
            After=network-online.target priceghost-network.service priceghost-postgres.service
            Wants=network-online.target
            Requires=priceghost-network.service priceghost-postgres.service

            [Container]
            ContainerName=priceghost-backend
            Image=localhost/priceghost-backend:${cfg.backendImageTag}
            Network=priceghost.network
            PodmanArgs=--network-alias=backend
            Environment=PORT=3001
            Environment=NODE_ENV=production
            EnvironmentFile=${cfg.backendEnvFile}
            Memory=${cfg.backendMemory}
            PidsLimit=500
            Ulimit=nofile=2048:4096
            LogDriver=journald
            LogOpt=tag=priceghost-backend

            [Service]
            RestrictAddressFamilies=~AF_ALG
            SystemCallArchitectures=native
            ExecStartPre=${backendEnvScript}
            Restart=always
            RestartSec=10
            TimeoutStartSec=120

            [Install]
            WantedBy=multi-user.target
          '';

          "containers/systemd/priceghost.container".text = ''
            [Unit]
            Description=PriceGhost Web UI
            After=network-online.target priceghost-network.service priceghost-backend.service
            Wants=network-online.target
            Requires=priceghost-network.service priceghost-backend.service

            [Container]
            ContainerName=priceghost
            Image=localhost/priceghost-frontend:${cfg.frontendImageTag}
            Network=priceghost.network
            PublishPort=${toString cfg.port}:80
            Memory=${cfg.frontendMemory}
            PidsLimit=500
            LogDriver=journald
            LogOpt=tag=priceghost

            [Service]
            RestrictAddressFamilies=~AF_ALG
            SystemCallArchitectures=native
            Restart=always
            RestartSec=10
            TimeoutStartSec=120

            [Install]
            WantedBy=multi-user.target
          '';

          "containers/systemd/priceghost-postgres-data.volume".text = ''
            [Volume]
            VolumeName=priceghost-postgres-data
          '';

          "containers/systemd/priceghost.network".text = ''
            [Network]
            NetworkName=priceghost
          '';
        };

        networking.firewall.allowedTCPPorts = [ cfg.port ];
      };
    };
}
