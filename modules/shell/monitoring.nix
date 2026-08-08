{ config, ... }:
let
  inherit (config.flake.lib) lazyApp;
  packagesFor =
    pkgs:
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
  systemPackages = { pkgs, ... }: {
    environment.systemPackages = packagesFor pkgs;
  };
in
{
  flake.modules = {
    nixos.shell = systemPackages;
    darwin.shell = systemPackages;
    homeManager.shell = { pkgs, ... }: {
      home.packages = packagesFor pkgs;
    };
  };
}
