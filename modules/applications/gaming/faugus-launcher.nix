_: {
  flake.modules.nixos.gaming =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.faugus-launcher ];
    };

  flake.modules.homeManager.applications =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      battleNetPreset = pkgs.writeText "faugus-launch-presets.json" (
        builtins.toJSON [
          # Battle.net / World of Warcraft
          "PROTON_NO_WM_DECORATION=1 PROTON_USE_NTSYNC=1 PROTON_ENABLE_WAYLAND=1 PROTON_ENABLE_NVAPI=1 mullvad-exclude gamemoderun gamescope -f -W 3440 -H 1440 -r 165"
        ]
      );
    in
    {
      xdg.desktopEntries.faugus-launcher = {
        name = "Faugus Launcher";
        exec = "gamemoderun env WINEFSYNC=1 WINEESYNC=1 DXVK_STATE_CACHE=1 faugus-launcher %U";
        icon = "faugus-launcher";
        type = "Application";
        categories = [ "Game" ];
        startupNotify = false;
        terminal = false;
      };

      home.activation.seedFaugusLaunchPresets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        target="${config.xdg.configHome}/faugus-launcher/presets.json"
        if [[ ! -e "$target" ]]; then
          ${pkgs.coreutils}/bin/install -Dm644 ${battleNetPreset} "$target"
        fi
      '';
    };
}
