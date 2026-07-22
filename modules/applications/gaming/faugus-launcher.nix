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
      faugusLaunchArguments = [
        # Battle.net / World of Warcraft
        "GAMEID=umu-worldofwarcraft mullvad-exclude"
        "GAMEID=umu-infinitefusion mullvad-exclude"
        "GAMEID=umu-infinitefusionkanto"
        "GAMEID=umu-pokemonnova"
        "GAMEID=umu-elderscrollsonline mullvad-exclude"
      ];
      faugusLaunchPresets = pkgs.writeText "faugus-launch-presets.json" (
        builtins.toJSON faugusLaunchArguments
      );
      launcherSettings = pkgs.writeText "faugus-launcher-settings" ''
        default-prefix="${config.home.homeDirectory}/Faugus"
        mangohud=False
        gamemode=True
        disable-hidraw=False
        prevent-sleep=False
        default-runner=""
        lossless-location=${config.home.homeDirectory}/.steam/steam/steamapps/common/Lossless Scaling/Lossless.dll
        discrete-gpu=False
        splash-disable=False
        system-tray=True
        start-boot=False
        mono-icon=True
        interface-mode=List
        show-labels=False
        enable-logging=False
        wayland-driver=True
        enable-wow64=False
        language=en_US
        show-hidden=False
        disable-updates=False
        gamepad-navigation=False
        start-minimized=False
        show-categories=False
      '';
      globalEnvironment = pkgs.writeText "faugus-launcher-environment" ''
        TZ=:/etc/localtime
        TZDIR=/usr/share/zoneinfo
        PROTON_NO_WM_DECORATION=1
        PROTON_USE_NTSYNC=1
        PROTON_ENABLE_NVAPI=1
        DXVK_HUD=0
      '';
    in
    {
      xdg.desktopEntries.faugus-launcher = {
        name = "Faugus Launcher";
        exec = "gamemoderun env WINEFSYNC=1 WINEESYNC=1 DXVK_HUD=0 DXVK_STATE_CACHE=1 faugus-launcher %U";
        icon = "faugus-launcher";
        type = "Application";
        categories = [ "Game" ];
        startupNotify = false;
        terminal = false;
      };

      home.activation.refreshFaugusLaunchPresets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        target="${config.xdg.configHome}/faugus-launcher/presets.json"
        ${pkgs.coreutils}/bin/install -Dm644 ${faugusLaunchPresets} "$target"
      '';

      home.activation.seedFaugusLauncherConfiguration = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        config_file="${config.xdg.configHome}/faugus-launcher/config.ini"
        if [[ ! -e "$config_file" ]]; then
          ${pkgs.coreutils}/bin/install -dm755 "${config.xdg.configHome}/faugus-launcher"

          while IFS= read -r setting; do
            printf '%s\n' "$setting" >> "$config_file"
          done < ${launcherSettings}
        fi

        environment_file="${config.xdg.configHome}/faugus-launcher/envar.txt"
        if [[ ! -e "$environment_file" ]]; then
          ${pkgs.coreutils}/bin/install -Dm644 ${globalEnvironment} "$environment_file"
        fi
      '';
    };
}
