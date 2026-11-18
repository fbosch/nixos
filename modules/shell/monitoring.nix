let
  systemPackages =
    { pkgs, ... }:
    {
      environment.systemPackages =
        with pkgs;
        [
          htop
          btop
          dust
          dua
          ncdu
          fastfetch
        ]
        ++ lib.optionals stdenv.hostPlatform.isLinux [
          s-tui
          microfetch
        ];
    };
in
{
  flake.modules = {
    nixos.shell = systemPackages;
    darwin.shell = systemPackages;
  };
}
