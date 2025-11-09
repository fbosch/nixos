{
  flake.modules.homeManager.applications = { pkgs, ... }: {
    home.packages = with pkgs; [ p7zip speedtest-cli ];
  };
}
