{ config, ... }:
{
  flake.modules.nixos.system =
    { pkgs, ... }:
    let
      inherit (config.flake.lib) lazyApp;

      lazyGParted = lazyApp pkgs {
        pkg = pkgs.gparted;
        desktopItems = [
          (pkgs.makeDesktopItem {
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
          })
        ];
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
        mission-center
      ];
    };
}
