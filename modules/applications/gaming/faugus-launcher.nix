_: {
  flake.modules.nixos.gaming =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.faugus-launcher ];
    };

  flake.modules.homeManager.applications = {
    xdg.desktopEntries.faugus-launcher = {
      name = "Faugus Launcher";
      exec = "gamemoderun env WINEFSYNC=1 WINEESYNC=1 DXVK_STATE_CACHE=1 faugus-launcher %U";
      icon = "faugus-launcher";
      type = "Application";
      categories = [ "Game" ];
      startupNotify = false;
      terminal = false;
    };
  };
}
