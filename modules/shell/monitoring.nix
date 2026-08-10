let
  systemPackages =
    { pkgs, ... }:
    {
      environment.systemPackages =
        with pkgs;
        [
          htop
          btop
          glances
          dust
          dua
          ncdu
          fastfetch
        ]
        ++ lib.optionals stdenv.isLinux [
          s-tui
          microfetch
          below
        ];
    };
in
{
  flake.modules = {
    nixos.shell = systemPackages;
    darwin.shell = systemPackages;
  };
}
