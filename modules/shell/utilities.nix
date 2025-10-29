{
  flake.modules.homeManager.shell = { pkgs, ... }: {
    home.packages = with pkgs; [
      eza
      lf
      yazi
      aichat
    ];
  };
}
