{
  flake.modules.homeManager.shell = _: {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;

      # Automatically load .envrc files
      config = {
        global = {
          # Disable the hints about using direnv allow
          warn_timeout = "24h";
        };
      };
    };
  };
}
