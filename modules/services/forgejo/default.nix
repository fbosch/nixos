{ config, ... }:
let
  flakeConfig = config;
  inherit (flakeConfig.flake.lib) sopsFiles sopsHelpers;
in
{
  flake.modules.nixos."services/forgejo" =
    { config
    , hostMeta
    , lib
    , pkgs
    , ...
    }:
    let
      adminUser = flakeConfig.flake.meta.user;
      forgejoAdmin = pkgs.writeShellApplication {
        name = "forgejo-admin";
        runtimeInputs = [ pkgs.forgejo-lts ];
        text = ''
          export FORGEJO_CUSTOM=/var/lib/forgejo/custom
          export FORGEJO_WORK_DIR=/var/lib/forgejo
          exec forgejo "$@"
        '';
      };
    in
    {
      services = {
        startupPolicy.applications.forgejo = {
          tier = lib.mkDefault "background";
          units = [
            {
              name = "forgejo.service";
              provider = "nixos";
            }
          ];
        };

        forgejo = {
          enable = lib.mkDefault true;
          package = lib.mkDefault pkgs.forgejo-lts;
          stateDir = "/var/lib/forgejo";
          repositoryRoot = "/var/lib/forgejo/data/forgejo-repositories";
          lfs = {
            enable = true;
            contentDir = "/var/lib/forgejo/data/lfs";
          };
          settings = {
            actions.ENABLED = false;
            migrations = {
              ALLOWED_DOMAINS = "api.github.com,github.com";
              ALLOW_LOCALNETWORKS = false;
              LOCKED_DOMAINS = true;
            };
            server = {
              DISABLE_SSH = true;
              DOMAIN = "rvn-srv";
              HTTP_ADDR = hostMeta.local;
              HTTP_PORT = 3000;
              ROOT_URL = "https://forgejo.corvus-corax.synology.me/";
            };
            service = {
              DISABLE_REGISTRATION = true;
            };
            session.COOKIE_SECURE = true;
          };
        };

        exposedPorts = lib.mkAfter [
          {
            service = "forgejo";
            tcpPorts = [ 3000 ];
          }
        ];
      };

      networking.firewall.allowedTCPPorts = [ 3000 ];

      environment.systemPackages = [ forgejoAdmin ];

      sops.secrets = {
        email = sopsHelpers.mkSecret sopsFiles.common sopsHelpers.rootOnly;
        forgejo-admin-password = sopsHelpers.mkSecret sopsFiles.containers sopsHelpers.rootOnly;
      };

      systemd.services.forgejo-admin-bootstrap = {
        after = [
          "forgejo.service"
          "sops-install-secrets.service"
        ];
        requires = [ "forgejo.service" ];
        wantedBy = [ "forgejo.service" ];
        script = ''
          export FORGEJO_CUSTOM=/var/lib/forgejo/custom
          export FORGEJO_WORK_DIR=/var/lib/forgejo

          if ${pkgs.sqlite}/bin/sqlite3 /var/lib/forgejo/data/forgejo.db \
            "SELECT 1 FROM user WHERE lower_name = '${adminUser.username}' LIMIT 1;" | ${pkgs.gnugrep}/bin/grep -qx 1; then
            exit 0
          fi

          email="$(<"$CREDENTIALS_DIRECTORY/admin-email")"
          password="$(<"$CREDENTIALS_DIRECTORY/admin-password")"
          exec ${pkgs.forgejo-lts}/bin/forgejo admin user create \
            --username '${adminUser.username}' \
            --email "$email" \
            --fullname '${adminUser.fullName}' \
            --admin \
            --must-change-password=false \
            --password "$password"
        '';
        serviceConfig = {
          LoadCredential = [
            "admin-email:${config.sops.secrets.email.path}"
            "admin-password:${config.sops.secrets.forgejo-admin-password.path}"
          ];
          NoNewPrivileges = true;
          ProtectProc = "invisible";
          User = "forgejo";
        };
      };
    };
}
