{
  flake.modules.homeManager.applications = { pkgs, ... }: {
    home.packages = with pkgs; [
      gimp
      pkgs.local.morgen
      pkgs.local.chromium-protonmail
    ];
  };
}
