{ config, ... }:
let
  inherit (config.flake.lib) sopsHelpers;
  inherit (config.flake.meta.user) username;
in
{
  # onWatch - API quota usage tracker with web dashboard
  # https://github.com/onllm-dev/onWatch
  #
  # Tracks Anthropic, GitHub Copilot, and OpenAI/Codex quota usage in real time.
  # Serves a Material Design 3 dashboard on port 9211.
  #
  # Provider tokens (Anthropic, Copilot, OpenAI) are extracted from opencode's
  # auth.json at container start time by a pre-start script, so no manual token
  # management is needed — they stay current as opencode refreshes them.
  #
  # SETUP:
  # 1. Add secrets to secrets/containers.yaml:
  #    sops secrets/containers.yaml
  #    Add: onwatch-admin-user, onwatch-admin-pass
  # 2. Access dashboard at http://<host>:9211

  flake.modules.nixos."services/containers/onwatch" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      cfg = config.services.onwatch-container;
      containersFile = ../../../secrets/containers.yaml;

      # Script that reads local auth state files and writes provider tokens into
      # a runtime env file that the container picks up via EnvironmentFile.
      # Runs as ExecStartPre so tokens are fresh on every (re)start.
      extractTokensScript = pkgs.writeShellScript "onwatch-extract-tokens" ''
        set -euo pipefail
        AUTH="${cfg.opencodeAuthFile}"
        CODEX_AUTH="${cfg.codexAuthFile}"
        OUT="${cfg.runtimeEnvFile}"
        now_ms="$(${pkgs.coreutils}/bin/date +%s)000"

        is_expired() {
          local expires="$1"

          if [ -z "$expires" ] || [ "$expires" = "0" ]; then
            return 1
          fi

          case "$expires" in
            *[!0-9]*) return 1 ;;
          esac

          [ "$expires" -le "$now_ms" ]
        }

        anthropic=""
        copilot=""
        openai=""
        codex=""

        if [ -f "$AUTH" ]; then
          anthropic=$(${pkgs.jq}/bin/jq -r '.anthropic.access // ""' "$AUTH")
          copilot=$(${pkgs.jq}/bin/jq -r '.["github-copilot"].access // ""' "$AUTH")
          openai=$(${pkgs.jq}/bin/jq -r '.openai.access // ""' "$AUTH")

          if is_expired "$(${pkgs.jq}/bin/jq -r '.openai.expires // 0' "$AUTH")"; then
            openai=""
            echo "onwatch-extract-tokens: openai token is expired in $AUTH, skipping" >&2
          fi

          if is_expired "$(${pkgs.jq}/bin/jq -r '.["github-copilot"].expires // 0' "$AUTH")"; then
            copilot=""
            echo "onwatch-extract-tokens: copilot token is expired in $AUTH, skipping" >&2
          fi
        else
          echo "onwatch-extract-tokens: $AUTH not found, skipping opencode token extraction" >&2
        fi

        if [ -f "$CODEX_AUTH" ]; then
          codex=$(${pkgs.jq}/bin/jq -r '.tokens.access_token // ""' "$CODEX_AUTH")
        fi

        # Backward-compatible fallback for existing setups that rely on
        # opencode OAuth state for Codex token injection.
        if [ -z "$codex" ]; then
          codex="$openai"
        fi

        {
          [ -n "$anthropic" ] && echo "ANTHROPIC_TOKEN=$anthropic"
          [ -n "$copilot"   ] && echo "COPILOT_TOKEN=$copilot"
          [ -n "$codex"     ] && echo "CODEX_TOKEN=$codex"
        } > "$OUT"

        ${pkgs.coreutils}/bin/chmod 400 "$OUT"
      '';
    in
    {
      options.services.onwatch-container = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 9211;
          description = "Port for onWatch web dashboard";
        };

        imageTag = lib.mkOption {
          type = lib.types.str;
          default = "2.11.19";
          description = "onWatch container image tag";
        };

        dataDir = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/onwatch";
          description = "Directory for onWatch SQLite database";
        };

        opencodeAuthFile = lib.mkOption {
          type = lib.types.str;
          description = "Host path to opencode auth.json; tokens are extracted at container start";
        };

        codexAuthFile = lib.mkOption {
          type = lib.types.str;
          description = "Host path to Codex auth.json; CODEX_TOKEN is extracted from tokens.access_token";
        };

        runtimeEnvFile = lib.mkOption {
          type = lib.types.str;
          default = "/run/onwatch-tokens.env";
          description = "Runtime file written by pre-start script containing provider tokens";
        };

        pollInterval = lib.mkOption {
          type = lib.types.int;
          default = 60;
          description = "Polling interval in seconds (10-3600)";
        };

        logLevel = lib.mkOption {
          type = lib.types.enum [
            "debug"
            "info"
            "warn"
            "error"
          ];
          default = "info";
          description = "Log level for onWatch";
        };

        memory = lib.mkOption {
          type = lib.types.str;
          default = "64m";
          description = "Memory limit for onWatch container";
        };
      };

      config = {
        services = {
          onwatch-container.opencodeAuthFile = lib.mkDefault "/home/${username}/.local/share/opencode/auth.json";
          onwatch-container.codexAuthFile = lib.mkDefault "/home/${username}/.codex/auth.json";

          containerPorts = lib.mkAfter [
            {
              service = "onwatch-container";
              tcpPorts = [ cfg.port ];
            }
          ];
        };

        sops = {
          secrets = sopsHelpers.mkSecretsWithOpts containersFile sopsHelpers.rootOnly [
            "onwatch-admin-user"
            "onwatch-admin-pass"
          ];

          templates."onwatch-env" = {
            content = ''
              ONWATCH_ADMIN_USER=${config.sops.placeholder.onwatch-admin-user}
              ONWATCH_ADMIN_PASS=${config.sops.placeholder.onwatch-admin-pass}
              ONWATCH_DB_PATH=/data/onwatch.db
              ONWATCH_POLL_INTERVAL=${toString cfg.pollInterval}
              ONWATCH_LOG_LEVEL=${cfg.logLevel}
              ONWATCH_HOST=0.0.0.0
            '';
            mode = "0400";
          };
        };

        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0755 65532 65532 -"
          # Ensure the runtime env file exists before the container first starts;
          # ExecStartPre will overwrite it with real tokens on each start.
          "f ${cfg.runtimeEnvFile} 0400 root root -"
        ];

        environment.etc."containers/systemd/onwatch.container".text = ''
          [Unit]
          Description=onWatch API Quota Tracker
          After=network-online.target
          Wants=network-online.target

          [Container]
          ContainerName=onwatch
          Image=ghcr.io/onllm-dev/onwatch:${cfg.imageTag}
          Exec=--debug
          PublishPort=${toString cfg.port}:9211
          Volume=${cfg.dataDir}:/data
          EnvironmentFile=${config.sops.templates."onwatch-env".path}
          EnvironmentFile=${cfg.runtimeEnvFile}
          PodmanArgs=--memory=${cfg.memory}
          LogDriver=journald
          LogOpt=tag=onwatch

          [Service]
          ExecStartPre=${extractTokensScript}
          Restart=always
          RestartSec=10
          TimeoutStartSec=120

          [Install]
          WantedBy=multi-user.target
        '';

        networking.firewall.allowedTCPPorts = [ cfg.port ];
      };
    };
}
