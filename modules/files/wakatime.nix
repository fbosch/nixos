{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules = {
    # NixOS module: Create SOPS template and symlink via tmpfiles
    nixos."files/wakatime" =
      { config, lib, ... }:
      let
        hasApiKey = config.sops.secrets ? wakapi-api-key;
        inherit (flakeConfig.flake.meta.user) username;
        homeDir = config.users.users.${username}.home;
        wakatimePath = "${homeDir}/.wakatime.cfg";
        templatePath = config.sops.templates."wakatime.cfg".path;
      in
      {
        config = lib.mkIf hasApiKey {
          # Create SOPS template with actual secret
          sops.templates."wakatime.cfg" = {
            content = ''
              [settings]
              api_url = https://wakapi.corvus-corax.synology.me/api
              api_key = ${config.sops.placeholder.wakapi-api-key}
            '';
            mode = "0600";
            owner = username;
          };

          # Create symlink from home directory to rendered template via tmpfiles
          systemd.tmpfiles.rules = [
            "L+ ${wakatimePath} - - - - ${templatePath}"
          ];
        };
      };

    # Darwin module: Create SOPS template and symlink via activation script
    darwin."files/wakatime" =
      { config, lib, ... }:
      let
        hasApiKey = config.sops.secrets ? wakapi-api-key;
        inherit (flakeConfig.flake.meta.user) username;
        homeDir = config.users.users.${username}.home;
        wakatimePath = "${homeDir}/.wakatime.cfg";
        templatePath = config.sops.templates."wakatime.cfg".path;
      in
      {
        config = lib.mkIf hasApiKey {
          # Create SOPS template with actual secret
          sops.templates."wakatime.cfg" = {
            content = ''
              [settings]
              api_url = https://wakapi.corvus-corax.synology.me/api
              api_key = ${config.sops.placeholder.wakapi-api-key}
            '';
            mode = "0600";
            owner = username;
          };

          # Create symlink from home directory to rendered template via activation script
          system.activationScripts.postActivation.text = lib.mkAfter ''
            ln -sf ${templatePath} ${wakatimePath}
            chown -h ${username} ${wakatimePath}
          '';
        };
      };
  };
}
