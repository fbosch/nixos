{
  flake.modules.nixos.system = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      gparted
      polkit
      polkit_gnome
      parted
      usbutils
      lsof
    ];
  };
}
