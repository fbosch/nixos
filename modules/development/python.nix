let
  packagesFor =
    pkgs:
      with pkgs;
      [
        (python3.withPackages (pythonPackages: [ pythonPackages.pyyaml ]))
        uv
      ]
      ++ lib.optionals stdenv.isLinux [
        python3Packages.evdev
      ];
  systemPackages = { pkgs, ... }: {
    environment.systemPackages = packagesFor pkgs;
  };
in
{
  flake.modules = {
    nixos.development = systemPackages;
    darwin.development = systemPackages;
    homeManager.development = { pkgs, ... }: {
      home.packages = packagesFor pkgs;
    };
  };
}
