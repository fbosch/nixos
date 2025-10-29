{
  flake.modules.homeManager.applications.productivity = { pkgs, ... }: {
    home.packages = with pkgs; [
      gimp
      pkgs.local.morgen
      pkgs.local.chromium-protonmail
    ];
  };
}
