_:
{
  flake.modules.homeManager."programs/<PROGRAM-NAME>" =
    { config
    , lib
    , pkgs
    , ...
    }:
    {
      config = {
        programs.<PROGRAM-NAME> = {
        enable = true;

        # Program-specific settings
        # Use lib.mkDefault for user-overridable values
        # Example:
        # theme = lib.mkDefault "dark";
        # fontSize = lib.mkDefault 12;
      };

      # Additional packages if needed
      home.packages = with pkgs; [
        # Related packages
      ];

      # XDG config files if needed
      # xdg.configFile."<PROGRAM-NAME>/config.conf".text = ''
      #   # Configuration content
      # '';
    };
};
}
