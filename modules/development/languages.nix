{
  flake.modules.homeManager.development =
    { pkgs, ... }:
    let
      luaWithSocket = pkgs.luajit.withPackages (ps: [ ps.luasocket ]);
    in
    {
      home.packages = with pkgs; [
        clang
        go
        rustc
        rustup
        zig
        luaWithSocket
      ];
    };
}
