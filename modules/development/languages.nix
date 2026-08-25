let
  systemPackages =
    { pkgs, ... }:
    let
      luaWithSocket = pkgs.luajit.withPackages (ps: [ ps.luasocket ]);
    in
    {
      environment.systemPackages = with pkgs; [
        clang
        go
        rustup
        zig
        luaWithSocket
      ];
    };
in
{
  flake.modules = {
    nixos.development = systemPackages;
    darwin.development = systemPackages;
  };
}
