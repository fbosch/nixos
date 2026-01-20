{ config, ... }:
{
  flake.modules.homeManager.development =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        git-credential-manager
        lazygit
        delta
        difftastic
        gitui
        gh
      ];

      programs.git = {
        enable = true;
        settings.credential = {
          helper = "manager";
          "https://github.com".username = config.flake.meta.user.github.username;
          credentialStore = "secretservice";
        };
      };
    };
}
