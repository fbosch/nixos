{
  flake.modules.homeManager.shell =
    { pkgs, lib, ... }:
    {
      home.packages =
        with pkgs;
        [
          htop
          btop
          dust
          dua
          fastfetch
        ]
        ++ lib.optionals pkgs.stdenv.isLinux [
          microfetch # Not available on Darwin
        ];
    };
}
