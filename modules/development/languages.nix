{
  flake.modules.homeManager."development/languages" = { pkgs, ... }: {
    home.packages = with pkgs; [
      python3
      python3Packages.evdev
      lua-language-server
    ];
  };
}
