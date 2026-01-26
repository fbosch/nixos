_: {
  flake.modules.nixos."services/atticd" =
    { config
    , lib
    , ...
    }:
    let
      cfg = config.services.atticd;
      ownerUser = lib.attrByPath [ "flake" "meta" "user" "username" ] "root" config;
      synologyDomain = lib.attrByPath [
        "flake"
        "meta"
        "synology"
        "domain"
      ] "corvus-corax.synology.me"
        config;
      atticHost = "attic.${synologyDomain}";
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
                atticHost
                "rvn-srv"
                "localhost"
                "127.0.0.1"
              ];
              api-endpoint = "https://${atticHost}/";
              substituter-endpoint = "https://${atticHost}/";
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
              "mnt-nas-web.automount"
              "network-online.target"
            ];
            wants = [
              "network-online.target"
              "mnt-nas-web.automount"
            ];
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
