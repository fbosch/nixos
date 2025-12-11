{
  flake.modules.homeManager.applications = { pkgs, ... }: {
    home.packages = with pkgs; [
      steam
      mangohud
      bottles # Wine prefix manager for Windows apps
      proton-ge-custom # Better Wine/Proton compatibility
    ];
  };
}
