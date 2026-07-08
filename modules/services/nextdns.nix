{ config, ... }:
let
  inherit (config.flake.lib) sopsHelpers;
in
{
  flake.modules.nixos."services/nextdns" =
    { config
    , lib
    , ...
    }:
    let
      cfg = config.services.nextdns;
      containersFile = ../../secrets/containers.yaml;
    in
    {
      options.services.nextdns.listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1:53";
        description = "Address and port for the local NextDNS DNS proxy.";
      };

      config = lib.mkIf cfg.enable {
        services.nextdns.arguments = lib.mkDefault [
          "-config-file"
          "/run/nextdns/nextdns.conf"
        ];

        sops.secrets."nextdns-profile-id" = lib.mkDefault (
          sopsHelpers.mkSecret containersFile sopsHelpers.rootOnly
        );

        systemd.services.nextdns = {
          after = [ "sops-install-secrets.service" ];
          wants = [ "sops-install-secrets.service" ];
          serviceConfig = {
            RuntimeDirectory = "nextdns";
            RuntimeDirectoryMode = "0700";
          };
          preStart = ''
            profile="$(tr -d '\n' < /run/secrets/nextdns-profile-id)"
            install -m 0600 /dev/null /run/nextdns/nextdns.conf
            cat > /run/nextdns/nextdns.conf <<EOF
            auto-activate false
            bogus-priv true
            cache-size 10MB
            control /run/nextdns/nextdns.sock
            detect-captive-portals false
            listen ${cfg.listenAddress}
            mdns disabled
            profile $profile
            report-client-info true
            setup-router false
            timeout 5s
            use-hosts true
            EOF
          '';
        };
      };
    };
}
