{
  flake.modules.nixos.system =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        attic-client
        gparted
        polkit
        polkit_gnome
        parted
        usbutils
        lsof
        ethtool
        icu
      ];
    };
}
