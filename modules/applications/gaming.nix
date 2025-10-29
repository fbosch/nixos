{
  flake.modules.homeManager.applications.gaming = { pkgs, ... }: {
    home.packages = with pkgs; [
      steam
    ];
  };
}
