{ inputs, ... }:
{
  flake.modules.homeManager.desktop =
    { pkgs, ... }:
    let
      pkgsStable = import inputs.nixpkgs-stable {
        inherit (pkgs.stdenv.hostPlatform) system;
        config.allowUnfree = true;
      };
    in
    {
      home.packages = [
        pkgs.wezterm
        pkgs.foot
        pkgs.kitty
        pkgs.ghostty
      ];
    };
}
