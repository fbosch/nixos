{ ... }:
{
  imports = [
    ./dotfiles.nix
    ./packages.nix
    ./programs.nix
    ./flatpak.nix
    ./theming/fonts.nix
    ./theming/gtk.nix
  ];
}
