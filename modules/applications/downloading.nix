{ config, ... }:
let
  inherit (config.flake.lib) lazyApp;
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
    in
    {
      home.packages =
        (with pkgs; [
          megasync
          p7zip
        ])
        ++ lazySpeedtestCli;
    };
}
