{ config, ... }:
let
  flakeConfig = config;
  inherit (flakeConfig.flake.lib) sopsHelpers;
  mkWakatime =
    config:
    let
      inherit (flakeConfig.flake.meta.user) username;
      homeDir = config.users.users.${username}.home;
    in
    {
      inherit username;
      hasApiKey = config ? sops;
      wakatimePath = "${homeDir}/.wakatime.cfg";
      templatePath = config.sops.templates."wakatime.cfg".path;
      baseConfig = {
        sops.secrets.wakapi-api-key = sopsHelpers.mkSecret ../../secrets/apis.yaml {
          mode = "0440";
          group = "wheel";
        };

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
      };
    };
in
{
  flake.modules = {
    # NixOS module: Create SOPS template and symlink via tmpfiles
    nixos."files/wakatime" =
      { config, lib, ... }:
      let
        args = mkWakatime config;
      in
      {
        config = lib.mkIf args.hasApiKey (
          lib.mkMerge [
            args.baseConfig
            {
              # Create symlink from home directory to rendered template via tmpfiles
              systemd.tmpfiles.rules = [
                "L+ ${args.wakatimePath} - - - - ${args.templatePath}"
              ];
            }
          ]
        );
      };

    # Darwin module: Create SOPS template and symlink via activation script
    darwin."files/wakatime" =
      { config, lib, ... }:
      let
        args = mkWakatime config;
      in
      {
        config = lib.mkIf args.hasApiKey (
          lib.mkMerge [
            args.baseConfig
            {
              # Create symlink from home directory to rendered template via activation script
              system.activationScripts.postActivation.text = lib.mkAfter ''
                ln -sf ${args.templatePath} ${args.wakatimePath}
                chown -h ${args.username} ${args.wakatimePath}
              '';
            }
          ]
        );
      };
  };
}
