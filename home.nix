{
  inputs,
  ...
}:
{
  imports = [
    inputs.zen-browser.homeModules.default
    inputs.flatpaks.homeManagerModules.nix-flatpak
    inputs.waybar-nixos-updates.homeManagerModules.default
    ./home/modules
  ];

  home.username = "fbb";
  home.homeDirectory = "/home/fbb";
  home.stateVersion = "25.05";
  systemd.user.startServices = "sd-switch";
}
