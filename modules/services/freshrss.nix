_: {
  flake.modules.nixos."services/freshrss" =
    { config
    , lib
    , ...
    }:
    let
      cfg = config.services.freshrss;
      synologyDomain = lib.attrByPath [
        "flake"
        "meta"
        "synology"
        "domain"
      ] "corvus-corax.synology.me"
        config;
    in
    {
      options.services.freshrss = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 8084;
          description = "Port for FreshRSS web interface (nginx reverse proxy).";
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Open firewall port for FreshRSS web interface.";
        };

        domain = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "freshrss.example.com";
          description = "Domain for FreshRSS. If null, uses synology domain from flake.meta.";
        };
      };

      config = lib.mkMerge [
        # SOPS secret configuration (only if sops is available)
        (lib.mkIf (config ? sops) {
          sops.secrets.freshrss-admin-password = {
            mode = "0440";
            owner = "freshrss";
            group = "freshrss";
            sopsFile = ../../secrets/containers.yaml;
          };
        })

        # Main FreshRSS configuration
        {
          services.freshrss = {
            enable = lib.mkDefault true;
            defaultUser = lib.mkDefault "admin";
            language = lib.mkDefault "en";
            database.type = lib.mkDefault "sqlite";
            authType = lib.mkDefault "form";
            api.enable = lib.mkDefault true;
            baseUrl = lib.mkDefault "https://${
              if cfg.domain != null then cfg.domain else "freshrss.${synologyDomain}"
            }";
            passwordFile = lib.mkIf (config ? sops) config.sops.secrets.freshrss-admin-password.path;
          };

          networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

          # Fix systemd service ordering - ensure SOPS secrets are installed before FreshRSS config
          systemd.services.freshrss-config = lib.mkIf (config ? sops) {
            after = [ "sops-install-secrets.service" ];
            wants = [ "sops-install-secrets.service" ];
          };
        }

        # Override the default nginx virtualHost to use custom port
        {
          services.nginx.virtualHosts.${config.services.freshrss.virtualHost}.listen = [
            {
              addr = "0.0.0.0";
              inherit (cfg) port;
            }
          ];
        }
      ];
    };
}
