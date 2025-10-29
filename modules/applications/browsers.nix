{
  flake.modules.homeManager.applications = { pkgs, ... }: {
    home.packages = with pkgs; [
      pkgs.local.helium-browser
    ];
  };
}
