{
  flake.modules.homeManager.development =
    { pkgs, meta, ... }:
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
          "https://github.com".username = meta.user.github.username;
          credentialStore = "gpg";
        };
      };
    };
}
