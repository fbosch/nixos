{ inputs, ... }:

{
  flake.modules.homeManager.base = { pkgs, ... }: {
    programs.home-manager.enable = true;
    systemd.user.startServices = "sd-switch";

    home = {
      username = "fbb";
      homeDirectory = "/home/fbb";
      stateVersion = "25.05";
    };

    home.packages = with pkgs; [
      # Hyprland packages
      hyprpaper
      hyprprop
      hyprpicker
      waycorner
      wl-clipboard
      waybar
      swaynotificationcenter
      libnotify
      rofi
      inputs.hyprland-contrib.packages.${pkgs.system}.grimblast

      # Terminals
      wezterm
      kitty
      ghostty

      # Audio
      pavucontrol

      # Theming
      nwg-look
      adw-gtk3
      colloid-gtk-theme

      # GNOME
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

      # Browsers
      pkgs.local.helium-browser

      # VPN
      protonvpn-gui
      protonvpn-cli

      # Productivity
      gimp
      pkgs.local.morgen

      # Development
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

      # Shell
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

      # Security
      pass
      gnupg
      pinentry-curses
      bitwarden-desktop

      # Gaming
      steam
    ];
  };
}