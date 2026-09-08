{
  flake.modules.homeManager.applications =
    { config
    , lib
    , pkgs
    , ...
    }:
    {
      options.programs.wl-relabel.rules = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Browser-owned wl-relabel rules.";
      };

      config = {
        home.packages = [ pkgs.local.wl-relabel ];

        xdg.configFile."wl-relabel/rules.toml".text = config.programs.wl-relabel.rules;
      };
    };
}
