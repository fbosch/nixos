{
  flake.modules.homeManager.shell.fish = { pkgs, ... }: {
    home.packages = with pkgs; [
      fish
      zsh
      dash
      starship
      zoxide
    ];
  };
}
