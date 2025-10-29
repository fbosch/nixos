{
  flake.modules.homeManager."shell/monitoring" = { pkgs, ... }: {
    home.packages = with pkgs; [
      htop
      btop
      dust
      mprocs
    ];
  };
}
