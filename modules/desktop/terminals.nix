{
  flake.modules.homeManager.desktop =
    { pkgs, pkgs-stable, ... }:
    {
      home.packages = [
        pkgs-stable.wezterm
        pkgs.kitty
        pkgs.ghostty
      ];
    };
}
