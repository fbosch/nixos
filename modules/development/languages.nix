{
  flake.modules.homeManager.development = { pkgs, ... }: {
    home.packages = with pkgs; [
      python3
      python3Packages.evdev
      lua-language-server
      go
      rustc
      rustup
    ];
  };
}
