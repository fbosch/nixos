{
  flake.modules.homeManager.applications =
    { config
    , lib
    , pkgs
    , ...
    }:
    {
      xdg.dataFile."icons/hicolor/scalable/apps/steam_app_worldofwarcraft.svg".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/assets/wow-icon.svg";

      xdg.dataFile."applications/steam_app_worldofwarcraft.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=World of Warcraft
        Exec=faugus-launcher --run "WINEPREFIX='${config.home.homeDirectory}/Faugus/battlenet' PROTONPATH='Proton-CachyOS Latest' WINE_SIMULATE_WRITECOPY=1 PROTON_ENABLE_WAYLAND=0 GAMEID=umu-worldofwarcraft mullvad-exclude gamemoderun '${lib.getExe pkgs.umu-launcher}' '${config.home.homeDirectory}/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/_retail_/Wow.exe' -launcherlogin -uid wow"
        Icon=steam_app_worldofwarcraft
        NoDisplay=true
        Terminal=false
        Categories=Game;
        Path=${config.home.homeDirectory}/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/_retail_
        StartupWMClass=steam_app_worldofwarcraft
      '';
    };
}
