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
        pkgsStable.wezterm
        pkgs.kitty
        pkgs.ghostty
      ];
    };
}
