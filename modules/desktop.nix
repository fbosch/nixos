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
  };
}
