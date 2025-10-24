{ ... }:
{
  imports = [
    ./base.nix
    ./i18n.nix
    ./vpn.nix
    ./packages.nix
    ./security.nix
    ./desktop/hyprland.nix
    ./desktop/audio.nix
  ];
}
