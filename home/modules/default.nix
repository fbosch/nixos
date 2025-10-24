{ ... }:
{
  imports = [
    ./dotfiles.nix
    ./packages.nix
    ./programs.nix
    ./flatpak.nix
    ./input.nix
    ./theming/fonts.nix
    ./theming/gtk.nix
  ];
}
