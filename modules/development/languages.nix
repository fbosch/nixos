let
  packagesFor =
    pkgs:
    let
      luaWithSocket = pkgs.luajit.withPackages (ps: [ ps.luasocket ]);
    in
    with pkgs;
    [
      clang
      go
      rustc
      rustup
      zig
      luaWithSocket
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
