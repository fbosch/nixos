_: {
  flake.modules.nixos."services/containers/openmemory" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      # OpenMemory source from GitHub
      openmemoryRev = "v1.2.3";
      openmemorySource = pkgs.fetchFromGitHub {
        owner = "CaviraOSS";
        repo = "OpenMemory";
        rev = openmemoryRev;
        hash = "sha256-VTzPg8NQx2/iTxD2GudOw4xlZhbBV70Zg2Q4iwap3Aw=";
      };

      # Script to build images using podman build (wraps existing Dockerfiles)
      buildImagesScript = pkgs.writeShellScriptBin "build-openmemory-images" ''
        set -euo pipefail

        if [ "$(id -u)" -ne 0 ]; then
          echo "This command must run as root so systemd can use the images."
          echo "Run: sudo build-openmemory-images"
          exit 1
        fi

        OPENMEMORY_TAG="${openmemoryRev}"

        TEMP_DIR=$(mktemp -d)
        trap "rm -rf $TEMP_DIR" EXIT

        echo "==> Copying OpenMemory source..."
        cp -a ${openmemorySource}/. "$TEMP_DIR"
        chmod -R u+w $TEMP_DIR

        if [ ! -d "$TEMP_DIR/backend" ]; then
          echo "Missing backend in build context"
          ls -la "$TEMP_DIR"
          exit 1
        fi

        if [ ! -d "$TEMP_DIR/dashboard" ]; then
          echo "Missing dashboard in build context"
          ls -la "$TEMP_DIR"
          exit 1
        fi

        cat > "$TEMP_DIR/dashboard/Dockerfile" <<'EOF'
        # ===== BUILD STAGE =====
        FROM node:20-alpine AS builder

        WORKDIR /app

        # Install dependencies
        COPY package*.json ./
        RUN npm install

        # Copy source code
        COPY . .

        # Build the Next.js application
        RUN npm run build

        # ===== PRODUCTION STAGE =====
        FROM node:20-alpine AS production

        WORKDIR /app

        # Install only production dependencies
        COPY package*.json ./
        RUN npm install --omit=dev

        # Copy built assets from builder
        COPY --from=builder /app/.next ./.next
        COPY --from=builder /app/public ./public
        COPY --from=builder /app/next.config.ts ./next.config.ts

        # Create a dedicated non-root user for security
        RUN addgroup -g 1001 -S nodejs \
         && adduser -u 1001 -S nextjs -G nodejs \
         && chown -R nextjs:nodejs /app

        USER nextjs

        # Expose the application port
        EXPOSE 3000

        # Set environment to production
        ENV NODE_ENV=production

        # Start the Next.js application
        CMD ["npm", "start"]
        EOF

        cd $TEMP_DIR

        echo "==> Building API server image..."
        ${pkgs.podman}/bin/podman build --format docker \
          -t localhost/openmemory:latest \
          -t localhost/openmemory:$OPENMEMORY_TAG \
          -f backend/Dockerfile \
          backend/

        echo ""
        echo "==> Building dashboard image..."
        ${pkgs.podman}/bin/podman build --format docker \
          -t localhost/openmemory-dashboard:latest \
          -t localhost/openmemory-dashboard:$OPENMEMORY_TAG \
          -f dashboard/Dockerfile \
          dashboard/

        echo ""
        echo "✓ Images built and loaded successfully!"
        echo "  localhost/openmemory:latest"
        echo "  localhost/openmemory:$OPENMEMORY_TAG"
        echo "  localhost/openmemory-dashboard:latest"
        echo "  localhost/openmemory-dashboard:$OPENMEMORY_TAG"
        echo ""
        echo "You can now rebuild your system to start the containers."
      '';

    in
    {
      options.services.openmemory-container = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 8380;
          description = "Port for OpenMemory API server";
        };

        dashboardPort = lib.mkOption {
          type = lib.types.port;
          default = 3380;
          description = "Port for OpenMemory dashboard";
        };

        imageTag = lib.mkOption {
          type = lib.types.str;
          default = "latest";
          description = ''
            OpenMemory image tag.

            Images are built declaratively using Nix dockerTools.
            Run 'build-openmemory-images' once before first activation.
          '';
        };

        buildImages = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Add 'build-openmemory-images' command to system packages.

            This builds OCI images using Nix and loads them into Podman.
            Run once before enabling the service:
              build-openmemory-images
              sudo nixos-rebuild switch
          '';
        };

        dataDir = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/openmemory";
          description = "Directory for persistent OpenMemory data";
        };

        # Core Configuration
        mode = lib.mkOption {
          type = lib.types.str;
          default = "standard";
          description = "Operating mode (standard/debug/production)";
        };

        tier = lib.mkOption {
          type = lib.types.str;
          default = "hybrid";
          description = "Memory tier (hybrid/local/cloud)";
        };

        # Embeddings Configuration
        embeddings = lib.mkOption {
          type = lib.types.str;
          default = "synthetic";
          description = "Embedding provider (synthetic/openai/gemini/ollama/aws)";
        };

        embeddingFallback = lib.mkOption {
          type = lib.types.str;
          default = "synthetic";
          description = "Fallback embedding provider";
        };

        vectorDim = lib.mkOption {
          type = lib.types.int;
          default = 256;
          description = "Vector dimension for embeddings";
        };

        # Provider API Keys
        openaiApiKey = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "OpenAI API key (leave empty to disable)";
        };

        geminiApiKey = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Gemini API key (leave empty to disable)";
        };

        ollamaUrl = lib.mkOption {
          type = lib.types.str;
          default = "http://localhost:11434";
          description = "Ollama server URL";
        };

        # Memory & Search
        minScore = lib.mkOption {
          type = lib.types.float;
          default = 0.3;
          description = "Minimum similarity score for memory retrieval";
        };

        # Auto Reflection
        autoReflect = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable automatic reflection";
        };

        reflectInterval = lib.mkOption {
          type = lib.types.int;
          default = 10;
          description = "Reflection interval in minutes";
        };

        # Decay System
        decayLambda = lib.mkOption {
          type = lib.types.float;
          default = 0.02;
          description = "Decay rate lambda";
        };

        decayIntervalMinutes = lib.mkOption {
          type = lib.types.int;
          default = 1440;
          description = "Decay interval in minutes";
        };

        decayReinforceOnQuery = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Reinforce memories on query";
        };

        # Rate Limiting
        rateLimitEnabled = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable rate limiting";
        };

        rateLimitMaxRequests = lib.mkOption {
          type = lib.types.int;
          default = 100;
          description = "Maximum requests per window";
        };

        # Dashboard
        enableDashboard = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable the web dashboard";
        };

        dashboardApiUrl = lib.mkOption {
          type = lib.types.str;
          default = "http://localhost:8380";
          description = "API URL for dashboard to connect to";
        };
      };

      config =
        let
          cfg = config.services.openmemory-container;
        in
        {
          # Make build script available if enabled
          environment.systemPackages = lib.mkIf cfg.buildImages [ buildImagesScript ];

          system.activationScripts.openmemoryBuildImages = lib.mkIf cfg.buildImages ''
            log_file=/var/log/openmemory-build.log
            mkdir -p /var/log
            echo "==> $(date -Iseconds) activation: checking images" >> "$log_file"
            missing=0

            if ! ${pkgs.podman}/bin/podman image exists localhost/openmemory:${cfg.imageTag}; then
              missing=1
            fi

            if ${lib.boolToString cfg.enableDashboard} && ! ${pkgs.podman}/bin/podman image exists localhost/openmemory-dashboard:${cfg.imageTag}; then
              missing=1
            fi

            if [ "$missing" -eq 1 ]; then
              echo "OpenMemory images missing; building..." | tee -a "$log_file"
              ${buildImagesScript}/bin/build-openmemory-images >> "$log_file" 2>&1
            fi
          '';

          services.containerPorts = lib.mkAfter [
            {
              service = "openmemory-container";
              tcpPorts = [ cfg.port ] ++ lib.optional cfg.enableDashboard cfg.dashboardPort;
            }
          ];

          systemd.tmpfiles.rules = [
            "d ${cfg.dataDir} 0755 root root -"
          ];

          environment.etc = lib.mkMerge [
            {
              "containers/systemd/openmemory.container".text = ''
                [Unit]
                Description=OpenMemory API Server
                After=network-online.target
                Wants=network-online.target

                [Container]
                ContainerName=openmemory
                Image=localhost/openmemory:${cfg.imageTag}
                Pull=never
                PublishPort=${toString cfg.port}:8080
                Volume=openmemory-data.volume:/data

                # Core Configuration
                Environment=OM_PORT=8080
                Environment=OM_MODE=${lib.escapeShellArg cfg.mode}
                Environment=OM_TIER=${lib.escapeShellArg cfg.tier}
                Environment=OM_DB_PATH=/data/openmemory.sqlite

                # Rate Limiting
                Environment=OM_RATE_LIMIT_ENABLED=${if cfg.rateLimitEnabled then "true" else "false"}
                Environment=OM_RATE_LIMIT_MAX_REQUESTS=${toString cfg.rateLimitMaxRequests}

                # Embeddings Configuration
                Environment=OM_EMBEDDINGS=${lib.escapeShellArg cfg.embeddings}
                Environment=OM_EMBEDDING_FALLBACK=${lib.escapeShellArg cfg.embeddingFallback}
                Environment=OM_VEC_DIM=${toString cfg.vectorDim}

                ${lib.optionalString (cfg.openaiApiKey != "") ''
                  Environment=OM_OPENAI_API_KEY=${lib.escapeShellArg cfg.openaiApiKey}
                ''}
                ${lib.optionalString (cfg.geminiApiKey != "") ''
                  Environment=OM_GEMINI_API_KEY=${lib.escapeShellArg cfg.geminiApiKey}
                ''}
                Environment=OM_OLLAMA_URL=${lib.escapeShellArg cfg.ollamaUrl}

                # Memory & Search
                Environment=OM_MIN_SCORE=${toString cfg.minScore}

                # Auto Reflection
                Environment=OM_AUTO_REFLECT=${if cfg.autoReflect then "true" else "false"}
                Environment=OM_REFLECT_INTERVAL=${toString cfg.reflectInterval}

                # Decay System
                Environment=OM_DECAY_LAMBDA=${toString cfg.decayLambda}
                Environment=OM_DECAY_INTERVAL_MINUTES=${toString cfg.decayIntervalMinutes}
                Environment=OM_DECAY_REINFORCE_ON_QUERY=${if cfg.decayReinforceOnQuery then "true" else "false"}

                # Health Check
                HealthCmd=wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1
                HealthInterval=30s
                HealthTimeout=10s
                HealthStartPeriod=30s
                HealthRetries=3

                LogDriver=journald
                LogOpt=tag=openmemory

                [Service]
                Restart=always
                RestartSec=10
                TimeoutStartSec=300

                [Install]
                WantedBy=multi-user.target
              '';

              "containers/systemd/openmemory-data.volume".text = ''
                [Volume]
                VolumeName=openmemory-data
              '';
            }

            (lib.mkIf cfg.enableDashboard {
              "containers/systemd/openmemory-dashboard.container".text = ''
                [Unit]
                Description=OpenMemory Dashboard
                After=network-online.target openmemory.service
                Wants=network-online.target
                Requires=openmemory.service

                [Container]
                ContainerName=openmemory-dashboard
                Image=localhost/openmemory-dashboard:${cfg.imageTag}
                Pull=never
                PublishPort=${toString cfg.dashboardPort}:3000
                Environment=NEXT_PUBLIC_API_URL=${lib.escapeShellArg cfg.dashboardApiUrl}

                # Health Check
                HealthCmd=wget --no-verbose --tries=1 --spider http://localhost:3000 || exit 1
                HealthInterval=30s
                HealthTimeout=10s
                HealthStartPeriod=30s
                HealthRetries=3

                LogDriver=journald
                LogOpt=tag=openmemory-dashboard

                [Service]
                Restart=always
                RestartSec=10
                TimeoutStartSec=300

                [Install]
                WantedBy=multi-user.target
              '';
            })
          ];

          networking.firewall.allowedTCPPorts = [
            cfg.port
          ]
          ++ lib.optional cfg.enableDashboard cfg.dashboardPort;
        };
    };
}
