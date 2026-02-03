_: {
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
              port = port;
              public_url = "http://localhost:${toString port}";
            };
          };
        }
        (lib.mkIf (config ? sops) {
          sops.secrets.wakapi-password-salt = {
            mode = lib.mkDefault "0440";
            group = lib.mkDefault "wheel";
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
