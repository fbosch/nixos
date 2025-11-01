{
  flake.modules.homeManager.applications = { pkgs, ... }: {
    home.packages = with pkgs; [ megasync p7zip ];
  };
}
