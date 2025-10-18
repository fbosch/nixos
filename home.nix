{
  config,
  system,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  imports = [
    inputs.zen-browser.homeModules.default
    inputs.flatpaks.homeManagerModules.nix-flatpak
    ./home/modules
  ];

  home.username = "fbb";
  home.homeDirectory = "/home/fbb";
  home.stateVersion = "25.05";
  systemd.user.startServices = "sd-switch";
}
