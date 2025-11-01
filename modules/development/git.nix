{
  flake.modules.homeManager.development = { pkgs, ... }: {
    home.packages = with pkgs; [
      git-credential-manager
      lazygit
      delta
      gh
    ];
    
    programs.git = {
      enable = true;
      settings.credential = {
        helper = "manager";
        "https://github.com".username = "fbosch";
        credentialStore = "gpg";
      };
    };
  };
}
