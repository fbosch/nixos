_: {
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
            description = "Whether to run attic watch-store to push builds.";
          };
        };
      };

      config = {
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
            RestartSec = "30s";
            # Don't limit restarts - we want it to keep trying
            StartLimitIntervalSec = 0;
          };
          # Use 'true' to ensure the service doesn't fail during activation
          # The actual attic commands will run after, but failures won't block boot
          script = ''
            set +e  # Don't exit on error
            ${pkgs.attic-client}/bin/attic login --set-default rvn ${cfg.endpoint} "$(cat ${tokenFile})" || echo "Warning: attic login failed, will retry..."
            ${pkgs.attic-client}/bin/attic watch-store ${cfg.cacheName} || echo "Warning: attic watch-store failed, will retry..."
          '';
        };
      };
    };
}
