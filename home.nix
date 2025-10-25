{
  inputs,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    inputs.zen-browser.homeModules.default
    inputs.flatpaks.homeManagerModules.nix-flatpak
    inputs.vicinae.homeManagerModules.default
    ./home/modules
  ];

  home = {
    username = "fbb";
    homeDirectory = "/home/fbb";
    stateVersion = "25.05";
  };
  systemd.user.startServices = "sd-switch";
}
