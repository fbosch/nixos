{ config, ... }:
let
  inherit (config.flake.lib) lazyApp lazyDesktopApp;
in
{
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
    in
    {
      home.packages =
        (with pkgs; [
          lazyMegasync
          p7zip
        ])
        ++ lazySpeedtestCli;
    };
}
