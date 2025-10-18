{ ... }:
{
  imports = [
    ./base.nix
    ./networking.nix
    ./packages.nix
    ./security.nix
    ./desktop/hyprland.nix
    ./desktop/audio.nix
  ];
}
