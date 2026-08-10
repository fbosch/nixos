{
  flake.modules.nixos.desktop = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      json-glib
      gtk4
      gtk4-layer-shell
      gnome-keyring
      gnome-tweaks
      gnome-themes-extra
      gnome-calculator
      gnomeExtensions.appindicator
      gnomeExtensions.blur-my-shell
      gnomeExtensions.mock-tray
      gucharmap
      networkmanagerapplet
    ];
  };
}
