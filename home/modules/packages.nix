{ pkgs, inputs, lib, ... }:
let
  packages = with pkgs; {
    hyprland = [
      hyprpaper
      hyprprop
      hyprpicker
      wl-clipboard
      (waybar.overrideAttrs (oldAttrs: {
        mesonFlags = oldAttrs.mesonFlags ++ [ "-Dexperimental=true" ];
      }))
      swaynotificationcenter
      libnotify
      rofi
      inputs.hyprland-contrib.packages.${pkgs.system}.grimblast
    ];

    terminals = [
      wezterm
      kitty
    ];

    audio = [ pavucontrol ];

    gnome = [
      gtk4
      gtk4-layer-shell
      gnome-keyring
      gnome-tweaks
      gnome-themes-extra
      gnomeExtensions.appindicator
      gnomeExtensions.blur-my-shell
      nemo-with-extensions
      loupe
      gucharmap
      networkmanagerapplet
      mission-center
    ];

    vpn = [
      protonvpn-gui
      protonvpn-cli
    ];

    theming = [ nwg-look adw-gtk3 colloid-gtk-theme ];

    creative = [ gimp ];

    development = [
      code-cursor
      cursor-cli
      codex
      lua-language-server
      git-credential-manager
      lazygit
      delta
      python3
      python3Packages.evdev
      tesseract
    ];

    shell = [
      ripgrep
      zoxide
      eza
      lf
      fish
      zsh
      dash
      starship
      htop
      btop
      dust
      mprocs
    ];

    security = [
      pass
      gnupg
      pinentry-curses
      bitwarden-desktop
    ];

    gaming = [ steam ];
  };
in { 
  home.packages = lib.flatten (lib.attrValues packages);
}
