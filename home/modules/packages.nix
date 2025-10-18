{ pkgs, lib, ... }:
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
      mako
      rofi
    ];

    terminals = [ wezterm kitty ];

    browsers = [ qutebrowser ];

    audio = [ pavucontrol ];

    gnome = [
      gtk4
      gtk4-layer-shell
      gnome-keyring
      gnome-tweaks
      gnomeExtensions.appindicator
      gnomeExtensions.blur-my-shell
      nemo-with-extensions
      loupe
    ];

    vpn = [ protonvpn-gui protonvpn-cli ];

    theming =
      [ nwg-look whitesur-gtk-theme whitesur-cursors whitesur-icon-theme ];

    development = [
      code-cursor
      cursor-cli
      lua-language-server
      git-credential-manager
      lazygit
      delta
    ];

    shell = [ ripgrep zoxide eza lf fish starship ];

    security = [ pass gnupg pinentry-curses bitwarden-desktop ];

    gaming = [ steam ];
  };
in { home.packages = lib.flatten (lib.attrValues packages); }
