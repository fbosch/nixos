{
  flake.modules.homeManager.development = {
    programs.neovim = {
      enable = true;
      withRuby = true;
      withPython3 = true;
    };
  };
}
