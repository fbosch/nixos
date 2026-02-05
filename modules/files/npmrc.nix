{ config, ... }:
let
  flakeConfig = config;
  mkNpmrc =
    config:
    let
      inherit (flakeConfig.flake.meta.user) username;
      homeDir = config.users.users.${username}.home;
    in
    {
      inherit username;
      hasToken = config.sops.secrets ? npm-personal-access-token;
      npmrcPath = "${homeDir}/.npmrc";
      templatePath = config.sops.templates."npmrc".path;
      baseConfig = {
        # Create SOPS template with actual secret
        sops.templates."npmrc" = {
          content = ''
            //registry.npmjs.org/:_authToken=${config.sops.placeholder.npm-personal-access-token}
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
    nixos."files/npmrc" =
      { config, lib, ... }:
      let
        args = mkNpmrc config;
      in
      {
        config = lib.mkIf args.hasToken (
          lib.mkMerge [
            args.baseConfig
            {
              # Create symlink from home directory to rendered template via tmpfiles
              systemd.tmpfiles.rules = [
                "L+ ${args.npmrcPath} - - - - ${args.templatePath}"
              ];
            }
          ]
        );
      };

    # Darwin module: Create SOPS template and symlink via activation script
    darwin."files/npmrc" =
      { config, lib, ... }:
      let
        args = mkNpmrc config;
      in
      {
        config = lib.mkIf args.hasToken (
          lib.mkMerge [
            args.baseConfig
            {
              # Create symlink from home directory to rendered template via activation script
              system.activationScripts.postActivation.text = lib.mkAfter ''
                ln -sf ${args.templatePath} ${args.npmrcPath}
                chown -h ${args.username} ${args.npmrcPath}
              '';
            }
          ]
        );
      };
  };
}
