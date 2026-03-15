{ config, ... }:
let
  inherit (config.flake.lib) sopsHelpers;
in
{
  flake.modules.nixos."services/attic-client" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      cfg = config.services.attic-client;
      endpoint = lib.removeSuffix "/" cfg.endpoint;
      cacheUrl = "${endpoint}/${cfg.cacheName}";
      tokenFile = config.sops.secrets.attic-admin-token.path;
      postBuildHookScript = pkgs.writeShellScript "attic-post-build-hook" (
        builtins.readFile (
          pkgs.replaceVars ../../scripts/attic/post-build-hook.sh {
            atticClient = pkgs.attic-client;
            inherit tokenFile;
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
      options.services.attic-client = {
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

        watchStore = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to push new build outputs to Attic via Nix post-build hook.";
          };
        };
      };

      config = {
        nix.settings = lib.mkMerge [
          {
            substituters = lib.mkBefore [ cacheUrl ];
            trusted-public-keys = [ cfg.publicKey ];
          }
          (lib.mkIf cfg.watchStore.enable {
            post-build-hook = postBuildHookScript;
          })
        ];

        sops.secrets.attic-admin-token = lib.mkIf cfg.watchStore.enable (
          sopsHelpers.mkSecret ../../secrets/development.yaml sopsHelpers.rootOnly
        );
      };
    };
}
