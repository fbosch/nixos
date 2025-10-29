{
  flake.modules.homeManager.shell = { pkgs, ... }: {
    home.packages = with pkgs; [
      htop
      btop
      dust
      mprocs
    ];
  };
}
