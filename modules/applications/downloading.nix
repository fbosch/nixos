{ config, ... }:
let
  inherit (config.flake.lib) lazyApp lazyDesktopApp;
in
{
  flake.modules.nixos.applications =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.media-downloader ];
    };

  flake.modules.homeManager.applications =
    { pkgs, ... }:
    let
      lazySpeedtestCli =
        map
          (
            exe:
            lazyApp pkgs {
              inherit exe;
              pkg = pkgs.speedtest-cli;
            }
          )
          [
            "speedtest"
            "speedtest-cli"
          ];

      lazyMegasync = lazyDesktopApp pkgs {
        pkg = pkgs.megasync;
        desktopItem = {
          name = "megasync";
          exec = "megasync";
          desktopName = "MEGAsync";
          genericName = "File Synchronizer";
          comment = "Easy automated syncing between your computers and your MEGA cloud drive";
          icon = ../../assets/icons/megasync.png;
          terminal = false;
          startupNotify = false;
          categories = [
            "Network"
            "System"
          ];
        };
      };
      proxyHost = config.flake.lib.hostMeta "rvn-srv";
    in
    {
      home.packages =
        (with pkgs; [
          lazyMegasync
          p7zip
        ])
        ++ lazySpeedtestCli;

      xdg.dataFile."media-downloader/settings/settings.ini".text = ''
        [General]
        ThemeName=Dark
        ProxySettingsType=Manual
        ProxySettingsCustomSource=http://${proxyHost.local}:8889
      '';
    };
}
