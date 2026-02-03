{ config, ... }:
let
  flakeConfig = config;

  # Shared SOPS template + symlink configuration for both NixOS and Darwin
  mkWakatimeModule =
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

        # Create symlink from home directory to rendered template
        # Use tmpfiles for NixOS, activation script for Darwin
        systemd.tmpfiles.rules = lib.mkIf (config ? systemd) [
          "L+ ${wakatimePath} - - - - ${templatePath}"
        ];

        system.activationScripts.postActivation.text = lib.mkIf (config ? system.activationScripts) (
          lib.mkAfter ''
            ln -sf ${templatePath} ${wakatimePath}
            chown ${username} ${wakatimePath}
          ''
        );
      };
    };
in
{
  flake.modules = {
    # NixOS module: Create SOPS template and symlink via tmpfiles
    nixos."files/wakatime" = mkWakatimeModule;

    # Darwin module: Create SOPS template and symlink via activation script
    darwin."files/wakatime" = mkWakatimeModule;

    # Home-manager module: Do nothing - file is managed at system level
    # We still need this module to exist so the import doesn't fail
    homeManager."files/wakatime" = _: { };
  };
}
