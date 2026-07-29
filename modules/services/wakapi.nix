{ inputs
, config
, ...
}:
let
  inherit (config.flake.lib) sopsHelpers;
in
{
  flake.modules.nixos."services/wakapi" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      port = 3033;
      secretspec = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.secretspec;
      secretspecManifest = pkgs.writeText "secretspec.toml" (builtins.readFile ../../secretspec.toml);
      wakapiSettingsFile =
        (pkgs.formats.yaml { }).generate "wakapi-settings"
          config.services.wakapi.settings;
    in
    {
      config = lib.mkMerge [
        {
          services.startupPolicy.applications.wakapi = {
            tier = lib.mkDefault "background";
            units = [
              {
                name = "wakapi.service";
                provider = "nixos";
              }
            ];
          };
        }
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
          sops.secrets.wakapi-password-salt = sopsHelpers.mkSecret ../../secrets/apis.yaml sopsHelpers.rootOnly;

          systemd.services.wakapi = {
            after = [ "sops-install-secrets.service" ];
            wants = [ "sops-install-secrets.service" ];
            # The upstream module supports EnvironmentFile but not a credential-aware command.
            script = lib.mkForce ''
              exec ${lib.getExe secretspec} --file ${secretspecManifest} run --profile systemd --scope wakapi --reason "Start Wakapi" -- ${lib.getExe config.services.wakapi.package} -config ${wakapiSettingsFile}
            '';
            serviceConfig = {
              LoadCredential = [
                "WAKAPI_PASSWORD_SALT:${config.sops.secrets.wakapi-password-salt.path}"
              ];
            };
          };
        })
        {
          networking.firewall.allowedTCPPorts = lib.mkAfter [ port ];
        }
      ];
    };
}
