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

      # Script that reads opencode's auth.json and writes provider tokens into
      # a runtime env file that the container picks up via EnvironmentFile.
      # Runs as ExecStartPre so tokens are fresh on every (re)start.
      extractTokensScript = pkgs.writeShellScript "onwatch-extract-tokens" ''
        set -euo pipefail
        AUTH="${cfg.opencodeAuthFile}"
        OUT="${cfg.runtimeEnvFile}"

        if [ ! -f "$AUTH" ]; then
          echo "onwatch-extract-tokens: $AUTH not found, skipping provider tokens" >&2
          : > "$OUT"
          exit 0
        fi

        anthropic=$(${pkgs.jq}/bin/jq -r '.anthropic.access // ""' "$AUTH")
        copilot=$(${pkgs.jq}/bin/jq -r '.["github-copilot"].access // ""' "$AUTH")
        openai=$(${pkgs.jq}/bin/jq -r '.openai.access // ""' "$AUTH")

        {
          [ -n "$anthropic" ] && echo "ANTHROPIC_TOKEN=$anthropic"
          [ -n "$copilot"   ] && echo "COPILOT_TOKEN=$copilot"
          [ -n "$openai"    ] && echo "CODEX_TOKEN=$openai"
        } > "$OUT"

        ${pkgs.coreutils}/bin/chmod 400 "$OUT"
      '';
    in
    {
      options.services.onwatch-container = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable onWatch API quota tracker container";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 9211;
          description = "Port for onWatch web dashboard";
        };

        imageTag = lib.mkOption {
          type = lib.types.str;
          default = "latest";
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

      config = lib.mkIf cfg.enable {
        services.onwatch-container.opencodeAuthFile = lib.mkDefault "/home/${username}/.local/share/opencode/auth.json";

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

        services.containerPorts = lib.mkAfter [
          {
            service = "onwatch-container";
            tcpPorts = [ cfg.port ];
          }
        ];

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
