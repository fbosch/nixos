_: {
  flake.modules.homeManager."programs/<PROGRAM-NAME>" =
    { lib, ... }:
    {
      config = {
        # Enabling programs.<PROGRAM-NAME> usually installs its package. Use this
        # module only when Home Manager owns material user configuration or lifecycle.
        programs."<PROGRAM-NAME>" = {
          enable = true;

          # Program-specific settings
          # Use lib.mkDefault for user-overridable values
          # Example:
          # theme = lib.mkDefault "dark";
          # fontSize = lib.mkDefault 12;
        };

        # XDG config files if needed
        # xdg.configFile."<PROGRAM-NAME>/config.conf".text = ''
        #   # Configuration content
        # '';
      };
    };
}
