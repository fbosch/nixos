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
      queueDir = "/var/lib/attic-upload";
      postBuildHook = pkgs.writeShellApplication {
        name = "attic-post-build-hook";
        runtimeInputs = [ pkgs.coreutils ];
        text = builtins.readFile (
          pkgs.replaceVars ./post-build-hook.sh {
            inherit queueDir;
          }
        );
      };
      uploadWorker = pkgs.writeShellApplication {
        name = "attic-upload";
        runtimeInputs = [ pkgs.coreutils ];
        text = builtins.readFile (
          pkgs.replaceVars ./upload-worker.sh {
            atticClient = pkgs.attic-client;
            inherit queueDir;
            inherit (cfg) cacheName;
            inherit endpoint;
          }
        );
      };
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
            post-build-hook = "${postBuildHook}/bin/attic-post-build-hook";
          })
        ];

        systemd.services.attic-upload = lib.mkIf cfg.watchStore.enable {
          description = "Upload Nix build outputs to Attic";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          environment.XDG_CONFIG_HOME = "${queueDir}/config";
          serviceConfig = {
            DynamicUser = true;
            StateDirectory = "attic-upload";
            StateDirectoryMode = "0750";
            LoadCredential = [ "attic-admin-token:${tokenFile}" ];
            Restart = "always";
            RestartSec = "10s";
            Nice = 19;
            CPUWeight = 10;
            CPUQuota = "20%";
            IOSchedulingClass = "idle";
            IOWeight = 10;
            PrivateTmp = true;
            ProtectHome = true;
            ProtectSystem = "strict";
          };
          script = "exec ${uploadWorker}/bin/attic-upload";
        };

        sops.secrets.attic-admin-token = lib.mkIf cfg.watchStore.enable (
          sopsHelpers.mkSecret ../../../secrets/development.yaml sopsHelpers.rootOnly
        );
      };
    };
}
