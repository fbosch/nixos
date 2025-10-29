{
  flake.modules.homeManager.shell.utilities = { pkgs, ... }: {
    home.packages = with pkgs; [
      eza
      lf
      yazi
      aichat
    ];
  };
}
