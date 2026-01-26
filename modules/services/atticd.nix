{ config, ... }:
{
  flake.modules.nixos."services/atticd" =
    { config
    , lib
    , ...
    }:
    let
      cfg = config.services.atticd;
      ownerUser = lib.attrByPath [ "flake" "meta" "user" "username" ] "root" config;
    in
    {
      config = lib.mkMerge [
        {
          services.atticd.enable = lib.mkDefault true;
        }
        (lib.mkIf cfg.enable {
          sops.templates."atticd-env" = {
            content = "ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=${config.sops.placeholder.atticd-jwt}\n";
            mode = "0400";
          };

          services.atticd = {
            environmentFile = config.sops.templates."atticd-env".path;
            settings = {
              listen = "0.0.0.0:8081";
              allowed-hosts = [
                "attic.corvus-corax.synology.me"
                "rvn-srv"
                "localhost"
                "127.0.0.1"
              ];
              api-endpoint = "https://attic.corvus-corax.synology.me/";
              substituter-endpoint = "https://attic.corvus-corax.synology.me/";
              storage = {
                type = "local";
                path = "/mnt/nas/web/attic";
              };
            };
          };

          systemd.services.atticd = {
            unitConfig.RequiresMountsFor = [
              "/mnt/nas/web"
              "/mnt/nas/web/attic"
            ];
            after = [
              "mnt-nas-web.mount"
              "network-online.target"
            ];
            wants = [ "network-online.target" ];
            serviceConfig.SupplementaryGroups = [ "users" ];
          };

          networking.firewall.allowedTCPPorts = [ 8081 ];

          systemd.tmpfiles.rules = [
            "d /mnt/nas/web/attic 0775 ${ownerUser} users -"
          ];

          sops.secrets.atticd-jwt = {
            mode = "0400";
          };
        })
      ];
    };
}
