{ config, ... }:
let
  inherit (config.flake.lib) lazyApp;
in
{
  flake.modules.homeManager.applications =
    { pkgs, ... }:
    let
      lazyHardinfo2 = lazyApp pkgs {
        pkg = pkgs.hardinfo2;
        desktopItems = [
          (pkgs.makeDesktopItem {
            name = "hardinfo2";
            exec = "hardinfo2";
            desktopName = "Hardinfo2";
            comment = "System Information and Benchmark";
            icon = "hardinfo2";
            terminal = false;
            startupNotify = true;
            categories = [
              "System"
              "Utility"
            ];
            keywords = [
              "linux"
              "kernel"
              "system"
              "hardware"
              "cpu"
              "processor"
              "memory"
              "benchmark"
              "test"
            ];
          })
        ];
      };
    in
    {
      home.packages = [
        lazyHardinfo2
        pkgs.resources
      ];
    };
}
