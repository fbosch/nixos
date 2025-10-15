{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  gtk = {
    enable = true;
    font.name = "Tahoma";
    gtk3.enable = true;
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = true;
    };
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = true;
    };
  };
}
