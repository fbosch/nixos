{
  flake.modules.homeManager.development =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        clang
        lua-language-server
        go
        rustc
        rustup
        zig
      ];
    };
}
