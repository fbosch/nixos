{
  flake.modules.homeManager.development =
    { pkgs, lib, ... }:
    {
      home.packages =
        with pkgs;
        [
          python3
          uv
        ]
        ++ lib.optionals pkgs.stdenv.isLinux [
          python3Packages.evdev # Linux input device library, not available on Darwin
        ];
    };
}
