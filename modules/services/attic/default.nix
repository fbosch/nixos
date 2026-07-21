{ config, ... }:
let
  inherit (config.flake.lib) sopsHelpers;
in
{
  flake.modules.nixos."services/attic" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      cfg = config.services.attic;
      endpoint = lib.removeSuffix "/" cfg.endpoint;
      cacheUrl = "${endpoint}/${cfg.cacheName}";
      tokenFile = config.sops.secrets.attic-admin-token.path;
      queueDirectory = "/var/lib/attic/queue";
      postBuildHookScript = pkgs.writeShellScript "attic-post-build-hook" (
        builtins.readFile (
          pkgs.replaceVars ./post-build-hook.sh {
            inherit queueDirectory;
          }
        )
      );
      uploadQueueScript = pkgs.writeShellScript "attic-upload-queue" (
        builtins.readFile (
          pkgs.replaceVars ./upload-queue.sh {
            atticClient = pkgs.attic-client;
            inherit tokenFile queueDirectory;
            inherit (cfg) cacheName;
            inherit endpoint;
          }
        )
      );
      synologyDomain = lib.attrByPath [
        "flake"
        "meta"
        "synology"
        "domain"
      ] "corvus-corax.synology.me"
        config;
    in
    {
      options.services.attic = {
        endpoint = lib.mkOption {
          type = lib.types.str;
          default = "https://attic.${synologyDomain}/";
          description = "Attic server endpoint URL.";
        };

        cacheName = lib.mkOption {
          type = lib.types.str;
          default = "nix-cache";
          description = "Attic cache name.";
        };

        publicKey = lib.mkOption {
          type = lib.types.str;
          default = "nix-cache:U6DL42pjWBPHYzWxhGK1W0Hh8nA0MD6sE0TtoWFqmAs=";
          description = "Trusted public key for the Attic cache.";
        };

        enableSubstituter = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to add the Attic cache as a Nix substituter on this host.";
        };

        watchStore = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to queue new build outputs for asynchronous upload to Attic.";
          };
        };
      };

      config = {
        nix.settings = lib.mkMerge [
          (lib.mkIf cfg.enableSubstituter {
            substituters = lib.mkBefore [ cacheUrl ];
            trusted-public-keys = [ cfg.publicKey ];
          })
          (lib.mkIf cfg.watchStore.enable {
            post-build-hook = postBuildHookScript;
          })
        ];

        systemd = lib.mkIf cfg.watchStore.enable {
          tmpfiles.rules = [ "d ${queueDirectory} 0700 root root -" ];

          paths.attic-upload-queue = {
            wantedBy = [ "multi-user.target" ];
            pathConfig.PathChanged = queueDirectory;
          };

          services.attic-upload-queue = {
            description = "Upload queued Nix build outputs to Attic";
            after = [
              "network-online.target"
              "sops-install-secrets.service"
            ];
            wants = [
              "network-online.target"
              "sops-install-secrets.service"
            ];
            serviceConfig = {
              Type = "oneshot";
              StateDirectory = "attic";
              StateDirectoryMode = "0700";
              TimeoutStartSec = "30m";
              UMask = "0077";
            };
            script = ''
              exec ${uploadQueueScript}
            '';
          };

          timers.attic-upload-queue = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnBootSec = "5m";
              OnUnitInactiveSec = "5m";
              Persistent = true;
            };
          };
        };

        sops.secrets.attic-admin-token = lib.mkIf cfg.watchStore.enable (
          sopsHelpers.mkSecret ../../../secrets/development.yaml sopsHelpers.rootOnly
        );
      };
    };
}
