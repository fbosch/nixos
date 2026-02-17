{ config, ... }:
let
  inherit (config.flake.lib) sopsHelpers;
in
{
  flake.modules.nixos."services/wakapi" =
    { config
    , lib
    , ...
    }:
    let
      port = 3033;
    in
    {
      config = lib.mkMerge [
        {
          services.wakapi = {
            enable = lib.mkDefault true;
            stateDir = lib.mkDefault "/var/lib/wakapi";
          };

          services.wakapi.settings = {
            server = {
              listen_ipv4 = "0.0.0.0";
              listen_ipv6 = "::";
              inherit port;
              public_url = "http://localhost:${toString port}";
            };
          };
        }
        (lib.mkIf (config ? sops) {
          sops.secrets.wakapi-password-salt = sopsHelpers.mkSecret ../../secrets/apis.yaml {
            mode = lib.mkDefault sopsHelpers.wheelReadable.mode;
            group = lib.mkDefault sopsHelpers.wheelReadable.group;
          };

          sops.templates."wakapi-env" = {
            content = ''
              WAKAPI_PASSWORD_SALT=${config.sops.placeholder.wakapi-password-salt}
            '';
            mode = "0400";
          };

          services.wakapi.environmentFiles = [
            config.sops.templates."wakapi-env".path
          ];
        })
        {
          networking.firewall.allowedTCPPorts = lib.mkAfter [ port ];
        }
      ];
    };
}
