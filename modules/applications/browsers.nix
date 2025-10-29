{
  flake.modules.homeManager."applications/browsers" = { pkgs, ... }: {
    home.packages = with pkgs; [
      pkgs.local.helium-browser
    ];
  };
}
