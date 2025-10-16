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
  REV = lib.escapeShellArg inputs.dotfiles.rev;
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
    kitty
    rofi
    gtk4
    gtk4-layer-shell
    gnome-keyring
    gnome-tweaks
    gnomeExtensions.appindicator
    gnomeExtensions.blur-my-shell
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
    (pkgs.waybar.overrideAttrs (oldAttrs: {
      mesonFlags = oldAttrs.mesonFlags ++ [ "-Dexperimental=true" ];
    }))
  ];


  home.activation.setupDotfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -euo pipefail
    
    if [ ! -d ${REPO} ]; then
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p ${REPO}
    fi
    
    $DRY_RUN_CMD ${pkgs.rsync}/bin/rsync -av --delete --chmod=u+w \
      ${lib.escapeShellArg inputs.dotfiles}/ ${REPO}/
    
    if [ ! -d ${REPO}/.git ]; then
      $DRY_RUN_CMD ${pkgs.git}/bin/git -C ${REPO} init
      $DRY_RUN_CMD ${pkgs.git}/bin/git -C ${REPO} remote add origin ${URL}
    fi
  '';
      # $DRY_RUN_CMD ${pkgs.git}/bin/git -C ${REPO} branch --set-upstream-to=origin/master

  home.activation.stowDotFiles = lib.hm.dag.entryAfter [ "setupDotfiles" "linkGeneration" ] ''
    set -euo pipefail
    cd ${REPO}
    $DRY_RUN_CMD ${pkgs.stow}/bin/stow --restow --verbose -t "$HOME" .
  '';
}
