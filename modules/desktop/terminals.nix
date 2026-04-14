_:
{
  flake.modules.homeManager.desktop =
    { pkgs, ... }:
    {
      home.packages = [
        pkgs.wezterm
        pkgs.foot
        pkgs.kitty
        pkgs.ghostty
      ];
    };
}
