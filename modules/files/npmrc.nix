{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules = {
    # NixOS module: Create SOPS template and symlink via tmpfiles
    nixos."files/npmrc" =
      { config, lib, ... }:
      let
        hasToken = config.sops.secrets ? npm-personal-access-token;
        inherit (flakeConfig.flake.meta.user) username;
        homeDir = config.users.users.${username}.home;
        npmrcPath = "${homeDir}/.npmrc";
        templatePath = config.sops.templates."npmrc".path;
      in
      {
        config = lib.mkIf hasToken {
          # Create SOPS template with actual secret
          sops.templates."npmrc" = {
            content = ''
              //registry.npmjs.org/:_authToken=${config.sops.placeholder.npm-personal-access-token}
            '';
            mode = "0600";
            owner = username;
          };

          # Create symlink from home directory to rendered template via tmpfiles
          systemd.tmpfiles.rules = [
            "L+ ${npmrcPath} - - - - ${templatePath}"
          ];
        };
      };

    # Darwin module: Create SOPS template and symlink via activation script
    darwin."files/npmrc" =
      { config, lib, ... }:
      let
        hasToken = config.sops.secrets ? npm-personal-access-token;
        inherit (flakeConfig.flake.meta.user) username;
        homeDir = config.users.users.${username}.home;
        npmrcPath = "${homeDir}/.npmrc";
        templatePath = config.sops.templates."npmrc".path;
      in
      {
        config = lib.mkIf hasToken {
          # Create SOPS template with actual secret
          sops.templates."npmrc" = {
            content = ''
              //registry.npmjs.org/:_authToken=${config.sops.placeholder.npm-personal-access-token}
            '';
            mode = "0600";
            owner = username;
          };

          # Create symlink from home directory to rendered template via activation script
          system.activationScripts.postActivation.text = lib.mkAfter ''
            ln -sf ${templatePath} ${npmrcPath}
            chown -h ${username} ${npmrcPath}
          '';
        };
      };
  };
}
