{
  flake.modules.nixos.development = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      nodejs
      fnm
      git
      clang
      cargo
      rustc
      zig
      gcc
      cmake
      gnumake
    ];
  };
}
