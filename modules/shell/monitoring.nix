{
  flake.modules.homeManager.shell =
    { pkgs, lib, ... }:
    {
      home.packages =
        with pkgs;
        [
          htop
          btop
          below
          glances
          dust
          dua
          ncdu
          fastfetch
        ]
        ++ lib.optionals pkgs.stdenv.isLinux [
          microfetch # Not available on Darwin
        ];
    };
}
