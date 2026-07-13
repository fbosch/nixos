{ config, ... }:
let
  inherit (config.flake.lib) lazyDesktopApp;
in
{
  flake.modules.homeManager.applications =
    { pkgs, ... }:
    let
      hardinfo2Icon = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/hardinfo2/hardinfo2/ebc19f3e5e3bbe7a806ff9384fbb226e767ddf0a/pixmaps/hardinfo2.svg";
        hash = "sha256-YD++5DwetKeOUHmCVW/57MBfKW94/dwRp/T/CPh0eo8=";
      };

      lazyHardinfo2 = lazyDesktopApp pkgs {
        pkg = pkgs.hardinfo2;
        desktopItem = {
          name = "hardinfo2";
          exec = "hardinfo2";
          desktopName = "Hardinfo2";
          comment = "System Information and Benchmark";
          icon = hardinfo2Icon;
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
        };
      };

      lazyResources = lazyDesktopApp pkgs {
        pkg = pkgs.resources;
        desktopItem = {
          name = "net.nokyan.Resources";
          exec = "resources";
          desktopName = "Resources";
          comment = "Keep an eye on system resources";
          icon = ../../assets/icons/resources.svg;
          terminal = false;
          startupNotify = true;
          categories = [ "System" ];
          keywords = [
            "System"
            "Resources"
            "Monitor"
            "Processes"
            "CPU"
            "RAM"
            "GPU"
            "Performance"
          ];
        };
      };
    in
    {
      home.packages = [
        lazyHardinfo2
        lazyResources
      ];
    };
}
