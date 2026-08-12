{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos."hosts/rvn-srv/home" =
    { config, ... }:
    let
      surgeSystem = {
        inherit (config.services.surge) package outputDir;
      };
    in
    {
      home-manager = {
        extraSpecialArgs = { inherit surgeSystem; };

        users.${flakeConfig.flake.meta.user.username}.imports = [
          (
            { surgeSystem, ... }:
            {
              services.surge = {
                inherit (surgeSystem) package outputDir;
                autostart = true;
                settings = {
                  general.default_download_dir = surgeSystem.outputDir;
                  network.proxy_url = "http://127.0.0.1:8889";
                };
              };
            }
          )
        ];
      };
    };
}
