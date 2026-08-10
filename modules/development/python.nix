let
  systemPackages =
    { pkgs, ... }:
    {
      environment.systemPackages =
        with pkgs;
        [
          (python3.withPackages (pythonPackages: [ pythonPackages.pyyaml ]))
          uv
        ]
        ++ lib.optionals stdenv.isLinux [
          python3Packages.evdev
        ];
    };
in
{
  flake.modules = {
    nixos.development = systemPackages;
    darwin.development = systemPackages;
  };
}
