{
  config,
  system,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  REPO = lib.escapeShellArg "${config.home.homeDirectory}/dotfiles";
  URL = lib.escapeShellArg "https://github.com/fbosch/dotfiles";
in
{
  imports = [
    inputs.zen-browser.homeModules.default
    inputs.flatpaks.homeManagerModules.nix-flatpak
    ./modules/services.nix
    ./modules/programs.nix
    ./modules/flatpak.nix
    ./modules/themes.nix
  ];

  home.username = "fbb";
  home.homeDirectory = "/home/fbb";
  home.stateVersion = "25.05";
  systemd.user.startServices = "sd-switch";

  home.packages = with pkgs; [
    hyprpaper
    hyprprop
    wezterm
    pavucontrol
    kitty
    rofi
    gtk4
    gtk4-layer-shell
    gnome-keyring
    gnome-tweaks
    gnomeExtensions.appindicator
    # gnomeExtensions.blur-my-shell
    nwg-look
    whitesur-gtk-theme
    whitesur-cursors
    whitesur-icon-theme
    nautilus
    loupe
    mako
    git-credential-manager
    stow
    pass
    delta
    ripgrep
    zoxide
    eza
    lf
    fish
    starship
    gnupg
    pinentry-curses
    steam
    bitwarden-desktop
    code-cursor
    (pkgs.waybar.overrideAttrs (oldAttrs: {
      mesonFlags = oldAttrs.mesonFlags ++ [ "-Dexperimental=true" ];
    }))
  ];

  home.activation.setupDotfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -euo pipefail
    
    if [ ! -d ${REPO}/.git ]; then
      $DRY_RUN_CMD ${pkgs.git}/bin/git clone --branch master ${URL} ${REPO}
    else
      $DRY_RUN_CMD ${pkgs.git}/bin/git -C ${REPO} pull origin master
    fi
  '';

  home.activation.stowDotFiles = lib.hm.dag.entryAfter [ "setupDotfiles" "linkGeneration" ] ''
    set -euo pipefail
    cd ${REPO}
    $DRY_RUN_CMD ${pkgs.stow}/bin/stow --adopt --restow --verbose -t "$HOME" .
  '';
}
