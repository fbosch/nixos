{ pkgs, inputs, lib, ... }:
let
  packages = with pkgs; {
    hyprland = [
      hyprpaper
      hyprprop
      hyprpicker
      waycorner
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
      ghostty
    ];

    audio = [ pavucontrol ];

    theming = [ nwg-look adw-gtk3 colloid-gtk-theme ];

    gnome = [
      gtk4
      gtk4-layer-shell
      gnome-keyring
      gnome-tweaks
      gnome-themes-extra
      gnome-calculator
      gnomeExtensions.appindicator
      gnomeExtensions.blur-my-shell
      nemo-with-extensions
      loupe
      gucharmap
      networkmanagerapplet
      mission-center
    ];

    browsers = [
      (pkgs.callPackage ../../packages/helium-browser { })
    ];

    vpn = [
      protonvpn-gui
      protonvpn-cli
    ];


    productivity = [ 
      gimp 
      (pkgs.callPackage ../../packages/morgen { })
    ];

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
      yazi
      aichat
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
