{
  flake.modules.nixos.shell = { pkgs, ... }: {
    environment.shells = [ pkgs.fish pkgs.dash ];
  };

  flake.modules.homeManager.shell = { pkgs, ... }: {
    home.packages = with pkgs; [ fish zsh dash starship zoxide ];
  };
}
