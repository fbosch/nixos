{
  flake.modules.homeManager.applications = { pkgs, ... }: {
    home.packages = with pkgs; [
      bottles # Wine prefix manager for running Windows applications
      wine # Base Wine support
    ];
  };
}
