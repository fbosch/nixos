{
  flake.modules.homeManager.applications = { pkgs, ... }: {
    home.packages = with pkgs; [
      gimp
      pkgs.local.chromium-protonmail
      pkgs.local.chromium-protoncalendar
    ];
  };
}
