{
  flake.modules.homeManager.applications = { pkgs, ... }: {
    home.packages = with pkgs; [ hardinfo2 ];
  };
}
