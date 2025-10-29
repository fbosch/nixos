{
  flake.modules.homeManager.shell = { pkgs, ... }: {
    home.packages = with pkgs; [
      fish
      zsh
      dash
      starship
      zoxide
    ];
  };
}
