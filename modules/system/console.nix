{
  flake.modules.nixos.system =
    { pkgs, config, ... }:
    {
      console = {
        earlySetup = true;
        font = "Lat2-Terminus16";
        packages = with pkgs; [ terminus_font ];
        colors = config.flake.lib.themes.zenwritten.console;
      };
    };
}
