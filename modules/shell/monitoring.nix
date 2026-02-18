{
  flake.modules.homeManager.shell =
    { pkgs, lib, ... }:
    {
      home.packages =
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
        ++ lib.optionals pkgs.stdenv.isLinux [
          # Not available on Darwin
          microfetch
          below
        ];
    };
}
