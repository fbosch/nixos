{
  flake.modules.homeManager.applications =
    { config
    , lib
    , pkgs
    , ...
    }:
    {
      xdg.dataFile = {
        "icons/hicolor/scalable/apps/steam_app_worldofwarcraft.svg".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/assets/wow-icon.svg";

        "applications/steam_app_worldofwarcraft.desktop".text = ''
          [Desktop Entry]
          Type=Application
          Name=World of Warcraft
          Exec=faugus-launcher --run "WINEPREFIX='${config.home.homeDirectory}/Faugus/battlenet' PROTONPATH='GE-Proton11-7-x86_64' WINE_SIMULATE_WRITECOPY=1 PROTON_ENABLE_WAYLAND=0 GAMEID=umu-worldofwarcraft mullvad-exclude '${lib.getExe pkgs.umu-launcher}' '${config.home.homeDirectory}/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/_retail_/Wow.exe' -launcherlogin -uid wow"
          Icon=steam_app_worldofwarcraft
          NoDisplay=true
          Terminal=false
          Categories=Game;
          Path=${config.home.homeDirectory}/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft/_retail_
          StartupWMClass=steam_app_worldofwarcraft
        '';

        "icons/hicolor/256x256/apps/steam_app_warcraftiii.png".source =
          config.lib.file.mkOutOfStoreSymlink "${config.xdg.dataHome}/faugus-launcher/icons/warcraft-iii.png";

        "applications/steam_app_warcraftiii.desktop".text = ''
          [Desktop Entry]
          Type=Application
          Name=Warcraft III
          Exec=faugus-launcher --run "WINEPREFIX='${config.home.homeDirectory}/Faugus/battlenet' PROTONPATH='GE-Proton11-WC3-CertFix' PROTON_ENABLE_WAYLAND=0 GAMEID=umu-warcraftiii '${lib.getExe pkgs.umu-launcher}' '${config.home.homeDirectory}/Faugus/battlenet/drive_c/Program Files (x86)/Warcraft III/Warcraft III Launcher.exe'"
          Icon=steam_app_warcraftiii
          NoDisplay=true
          Terminal=false
          Categories=Game;
          Path=${config.home.homeDirectory}/Faugus/battlenet/drive_c/Program Files (x86)/Warcraft III
          StartupWMClass=warcraft iii.exe
        '';
      };
    };
}
