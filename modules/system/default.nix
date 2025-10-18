{ ... }:
{
  imports = [
    ./base.nix
    ./vpn.nix
    ./packages.nix
    ./security.nix
    ./desktop/hyprland.nix
    ./desktop/audio.nix
  ];
}
