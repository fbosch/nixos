{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos."hosts/rvn-srv/home" =
    { config, ... }:
    {
      home-manager.users.${flakeConfig.flake.meta.user.username} = {
        imports = flakeConfig.flake.lib.resolveHm [
          # Server preset modules for Home Manager
          "users"
          "dotfiles"
          "security"
          "development"
          "shell"
          "applications/surge"

          # Secrets for home-manager context
          "secrets"
        ];

        services.surge = {
          inherit (config.services.surge) package outputDir;
          autostart = true;
          settings = {
            general.default_download_dir = config.services.surge.outputDir;
            network.proxy_url = "http://127.0.0.1:8889";
          };
        };
      };
    };
}
