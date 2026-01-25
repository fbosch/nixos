{
  flake.modules.homeManager.desktop =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        gtk4
        gtk4-layer-shell
        gnome-keyring
        gnome-extension-manager
        gnome-tweaks
        gnome-themes-extra
        gnome-calculator
        gnomeExtensions.appindicator
        gnomeExtensions.blur-my-shell
        gnomeExtensions.home-assistant-extension
        gnomeExtensions.mock-tray
        gucharmap
        networkmanagerapplet
        mission-center
      ];
    };
}
