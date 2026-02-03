_: {
  flake.modules.nixos."services/wakapi" =
    { config
    , lib
    , ...
    }:
    let
      port = 3033;
      hasSopsSalt = lib.hasAttrByPath [ "sops" "placeholder" "wakapi-password-salt" ] config;
    in
    {
      config = lib.mkMerge [
        {
          services.wakapi = {
            enable = lib.mkDefault true;
            stateDir = lib.mkDefault "/var/lib/wakapi";
            settings = lib.mkDefault {
              server = {
                listen_ipv4 = "0.0.0.0";
                listen_ipv6 = "::";
                port = port;
                public_url = "http://localhost:${toString port}";
              };
            };
          };
        }
        (lib.mkIf hasSopsSalt {
          sops.secrets.wakapi-password-salt = {
            mode = "0400";
            group = "wheel";
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
