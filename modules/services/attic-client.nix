_:
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
    in
    {
      options.services.attic-client = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to enable the Attic client configuration.";
        };

        endpoint = lib.mkOption {
          type = lib.types.str;
          default = "https://attic.corvus-corax.synology.me/";
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
            description = "Whether to run attic watch-store to push builds.";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        nix.settings = {
          substituters = lib.mkBefore [ cacheUrl ];
          trusted-public-keys = [ cfg.publicKey ];
        };

        sops.secrets.attic-admin-token = lib.mkIf cfg.watchStore.enable {
          mode = "0400";
        };

        systemd.services.attic-watch-store = lib.mkIf cfg.watchStore.enable {
          description = "Attic watch-store push";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "simple";
            User = "root";
            Restart = "always";
            RestartSec = "5s";
          };
          script = ''
            ${pkgs.attic-client}/bin/attic login --set-default rvn ${cfg.endpoint} "$(cat ${tokenFile})"
            ${pkgs.attic-client}/bin/attic watch-store ${cfg.cacheName}
          '';
        };
      };
    };
}
