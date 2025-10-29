{
  flake.modules.homeManager."development/editors" = { pkgs, ... }: {
    home.packages = with pkgs; [
      code-cursor
      cursor-cli
    ];
  };
}
