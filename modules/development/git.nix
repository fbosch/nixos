{
  flake.modules.homeManager.development = {
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
