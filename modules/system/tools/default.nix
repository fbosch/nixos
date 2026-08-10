{
  flake.modules.nixos.system =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        attic-client
        gparted
        mission-center
        polkit
        polkit_gnome
        parted
        usbutils
        lsof
        ethtool
        chafa
        file
        icu
        dig
        duf
        lazyjournal
      ];
    };
}
