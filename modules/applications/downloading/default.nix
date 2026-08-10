{ config, ... }:
let
  inherit (config.flake.lib) lazyApp lazyDesktopApp;
  packagesFor =
    pkgs:
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
          icon = ./megasync.png;
          terminal = false;
          startupNotify = false;
          categories = [
            "Network"
            "System"
          ];
        };
      };
    in
    [
      lazyMegasync
      pkgs.p7zip
    ]
    ++ lazySpeedtestCli;
in
{
  flake.modules.nixos.applications =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.media-downloader ] ++ packagesFor pkgs;
    };

  flake.modules.homeManager.applications =
    { pkgs, ... }:
    let
      proxyHost = config.flake.meta.hosts.rvn-srv;
    in
    {
      xdg.dataFile."media-downloader/settings/settings.ini".text = ''
        [General]
        ThemeName=Dark
        ProxySettingsType=Manual
        ProxySettingsCustomSource=http://${proxyHost.local}:8889
      '';
    };
}
