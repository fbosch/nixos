{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos.system =
    { pkgs, ... }:
    {
      console = {
        earlySetup = true;
        font = "Lat2-Terminus16";
        packages = with pkgs; [ terminus_font ];
        colors = flakeConfig.flake.lib.themes.zenwritten.console;
      };
    };
}
