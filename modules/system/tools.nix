{ config, ... }:
{
  flake.modules.nixos.system =
    { pkgs, ... }:
    let
      inherit (config.flake.lib) lazyDesktopApp;

      lazyGParted = lazyDesktopApp pkgs {
        pkg = pkgs.gparted;
        desktopItem = {
          name = "gparted";
          exec = "gparted %f";
          desktopName = "GParted";
          genericName = "Partition Editor";
          comment = "Create, reorganize, and delete partitions";
          icon = ../../assets/icons/gparted.svg;
          terminal = false;
          startupNotify = true;
          categories = [
            "GNOME"
            "System"
            "Filesystem"
          ];
          keywords = [ "Partition" ];
        };
      };

      lazyMissionCenter = lazyDesktopApp pkgs {
        pkg = pkgs.mission-center;
        exe = "missioncenter";
        desktopItem = {
          name = "io.missioncenter.MissionCenter";
          exec = "missioncenter";
          desktopName = "Mission Center";
          icon = ../../assets/icons/mission-center.svg;
          terminal = false;
          startupNotify = true;
          categories = [
            "GTK"
            "System"
            "Monitor"
          ];
          keywords = [
            "Task manager"
            "Resource monitor"
            "System monitor"
            "CPU"
            "GPU"
            "Disk"
            "Memory"
            "Network"
          ];
        };
      };
    in
    {
      environment.systemPackages = with pkgs; [
        attic-client
        lazyGParted
        polkit
        polkit_gnome
        parted
        usbutils
        lsof
        ethtool
        file
        icu
        dig
        duf
        lazyjournal
        lazyMissionCenter
      ];
    };
}
