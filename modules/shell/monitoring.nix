{ config, ... }:
let
  inherit (config.flake.lib) lazyApp;
  systemPackages =
    { pkgs, ... }:
    {
      environment.systemPackages =
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
        ++ lib.optionals stdenv.isLinux [
          s-tui
          microfetch
          (lazyApp pkgs below)
        ];
    };
in
{
  flake.modules = {
    nixos.shell = systemPackages;
    darwin.shell = systemPackages;
  };
}
