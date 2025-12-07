{
  flake.modules.homeManager.development = { pkgs, ... }: {
    home.packages = with pkgs; [
      clang
      nodejs
      lua-language-server
      go
      rustc
      rustup
      zig
    ];
  };
}
