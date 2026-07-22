{ config, ... }:
let
  inherit (config.flake.lib) sopsHelpers startupPolicy;
in
{
  flake.modules.nixos."services/containers/openmemory" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      # OpenMemory source from GitHub
      openmemoryRev = "v1.2.3";
      openmemorySecretsFile = ../../../secrets/containers.yaml;
      openmemorySource = pkgs.fetchFromGitHub {
        owner = "CaviraOSS";
        repo = "OpenMemory";
        rev = openmemoryRev;
        hash = "sha256-VTzPg8NQx2/iTxD2GudOw4xlZhbBV70Zg2Q4iwap3Aw=";
      };

      # Script to build images using podman build (wraps existing Dockerfiles)
      mkBuildImagesScript =
        imageTag:
        pkgs.writeShellScriptBin "build-openmemory-images" ''
          set -euo pipefail

          if [ "$(id -u)" -ne 0 ]; then
            echo "This command must run as root so systemd can use the images."
            echo "Run: sudo build-openmemory-images"
            exit 1
          fi

          OPENMEMORY_TAG="${imageTag}"

          TEMP_DIR=$(mktemp -d)
          trap "rm -rf $TEMP_DIR" EXIT

          echo "==> Copying OpenMemory source..."
          cp -a ${openmemorySource}/. "$TEMP_DIR"
          chmod -R u+w "$TEMP_DIR"

          if [ ! -d "$TEMP_DIR/backend" ]; then
            echo "Missing backend in build context"
            ls -la "$TEMP_DIR"
            exit 1
          fi

          cd "$TEMP_DIR"

          echo "==> Building API server image..."
          ${pkgs.podman}/bin/podman build --format docker \
            -t localhost/openmemory:$OPENMEMORY_TAG \
            -f backend/Dockerfile \
            backend/

          echo ""
          echo "✓ Images built and loaded successfully!"
          echo "  localhost/openmemory:$OPENMEMORY_TAG"
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

        imageTag = lib.mkOption {
          type = lib.types.str;
          default = openmemoryRev;
          description = ''
            OpenMemory image tag.

            Images are built locally from the pinned OpenMemory revision.
            Run 'build-openmemory-images' once before first activation.
          '';
        };

        buildImages = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Add the 'build-openmemory-images' command to system packages.

            Run 'sudo build-openmemory-images' before the first activation and after
            changing imageTag.
            This command builds OCI images and loads them into Podman.
            Rebuilding does not build images automatically.
              sudo nixos-rebuild switch
          '';
        };

        dataDir = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/openmemory";
          description = "Directory for persistent OpenMemory data (used when useHostStorage = true)";
        };

        useHostStorage = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = "Store data on the host at dataDir instead of a Podman volume (null defaults to true when dataDir is set)";
        };

        runAsUser = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Host user to run the API container as when using host storage";
        };

        runAsGroup = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Host group to run the API container as when using host storage";
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

      };

      config =
        let
          cfg = config.services.openmemory-container;
          buildImagesScript = mkBuildImagesScript cfg.imageTag;
          hostUser =
            if cfg.runAsUser == null then
              null
            else
              lib.attrByPath [ "users" "users" cfg.runAsUser ] null config;
          hostGroup =
            if cfg.runAsGroup == null then
              null
            else
              lib.attrByPath [ "users" "groups" cfg.runAsGroup ] null config;
          hostUid = if hostUser == null then null else hostUser.uid or null;
          hostGid = if hostGroup == null then null else hostGroup.gid or null;
          useHostStorageEffective =
            if cfg.useHostStorage != null then cfg.useHostStorage else cfg.dataDir != "/var/lib/openmemory";
        in
        {
          services.startupPolicy.applications.openmemory = {
            tier = lib.mkDefault "background";
            units = [
              {
                name = "openmemory.service";
                provider = "quadlet";
              }
            ];
          };

          # Make build script available if enabled
          environment.systemPackages = lib.mkIf cfg.buildImages [ buildImagesScript ];

          services.exposedPorts = lib.mkAfter [
            {
              service = "openmemory-container";
              tcpPorts = [ cfg.port ];
            }
          ];

          systemd.tmpfiles.rules = [
            "d ${cfg.dataDir} 0755 root root -"
          ];

          sops = {
            secrets.openmemory-api-key = sopsHelpers.mkSecret openmemorySecretsFile sopsHelpers.rootOnly;
            templates."openmemory-api-key-env" = {
              content = ''
                OM_API_KEY=${config.sops.placeholder.openmemory-api-key}
                OM_OPENAI_API_KEY=${config.sops.placeholder.openai-api-key}
              '';
              mode = "0400";
            };
          };

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
                ${lib.optionalString (useHostStorageEffective && hostUid != null) "User=${toString hostUid}"}
                ${lib.optionalString (useHostStorageEffective && hostGid != null) "Group=${toString hostGid}"}
                PublishPort=${toString cfg.port}:8080
                ${
                  if useHostStorageEffective then
                    "Volume=${cfg.dataDir}:/data"
                  else
                    "Volume=openmemory-data.volume:/data"
                }

                # Core Configuration
                Environment=OM_PORT=8080
                Environment=OM_MODE=${lib.escapeShellArg cfg.mode}
                Environment=OM_TIER=${lib.escapeShellArg cfg.tier}
                Environment=OM_DB_PATH=/data/openmemory.sqlite
                EnvironmentFile=${config.sops.templates."openmemory-api-key-env".path}

                # Rate Limiting
                Environment=OM_RATE_LIMIT_ENABLED=${if cfg.rateLimitEnabled then "true" else "false"}
                Environment=OM_RATE_LIMIT_MAX_REQUESTS=${toString cfg.rateLimitMaxRequests}

                # Embeddings Configuration
                Environment=OM_EMBEDDINGS=${lib.escapeShellArg cfg.embeddings}
                Environment=OM_EMBEDDING_FALLBACK=${lib.escapeShellArg cfg.embeddingFallback}
                Environment=OM_VEC_DIM=${toString cfg.vectorDim}

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

                Memory=1g
                PidsLimit=500
                Ulimit=nofile=2048:4096

                # Health Check
                HealthCmd=wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1
                HealthInterval=30s
                HealthTimeout=10s
                HealthStartPeriod=30s
                HealthRetries=3

                LogDriver=journald
                LogOpt=tag=openmemory

                [Service]
                RestrictAddressFamilies=~AF_ALG
                SystemCallArchitectures=native
                Restart=always
                RestartSec=10
                CPUQuota=200%
                TimeoutStartSec=300

                [Install]
                WantedBy=${(startupPolicy.quadlet config "openmemory.service").target}
              '';

            }

            (lib.mkIf (!useHostStorageEffective) {
              "containers/systemd/openmemory-data.volume".text = ''
                [Volume]
                VolumeName=openmemory-data
              '';
            })
          ];

          networking.firewall.allowedTCPPorts = [
            cfg.port
          ];
        };
    };
}
