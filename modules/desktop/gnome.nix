{
  flake.modules.homeManager."desktop/gnome" = { pkgs, ... }: {
    home.packages = with pkgs; [
      gtk4
      gtk4-layer-shell
      gnome-keyring
      gnome-tweaks
      gnome-themes-extra
      gnome-calculator
      gnomeExtensions.appindicator
      gnomeExtensions.blur-my-shell
      nemo-with-extensions
      loupe
      gucharmap
      networkmanagerapplet
      mission-center
    ];
  };
}
