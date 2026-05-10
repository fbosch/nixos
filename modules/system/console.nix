let
  zenwritten = import ../../assets/themes/zenwritten.nix;
in
{
  flake.modules.nixos.system =
    { pkgs, ... }:
    {
      console = {
        earlySetup = true;
        font = "Lat2-Terminus16";
        packages = with pkgs; [ terminus_font ];
        colors = zenwritten.console;
      };
    };
}
