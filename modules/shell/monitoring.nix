{ config, ... }:
let
  inherit (config.flake.lib) lazyApp;
in
{
  flake.modules.homeManager.shell =
    { pkgs, lib, ... }:
    {
      home.packages =
        with pkgs;
        [
          htop
          btop
          (lazyApp pkgs glances)
          dust
          dua
          ncdu
          fastfetch
        ]
        ++ lib.optionals pkgs.stdenv.isLinux [
          # Not available on Darwin
          s-tui
          microfetch
          (lazyApp pkgs below)
        ];
    };
}
