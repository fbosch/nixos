{
  flake.modules.homeManager.development =
    { pkgs, ... }:
    let
      luaWithSocket = pkgs.lua5_2.withPackages (ps: [ ps.luasocket ]);
    in
    {
      home.packages = with pkgs; [
        clang
        lua-language-server
        go
        rustc
        rustup
        zig
        luaWithSocket
      ];
    };
}
