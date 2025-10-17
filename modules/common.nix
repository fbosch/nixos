{ config, pkgs, ... }:
{
  time.timeZone = "Europe/Copnhagen";
  i18n.defaultLocale = "en_DK.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "da_DK.UTF-8";
    LC_IDENTIFICATION = "da_DK.UTF-8";
    LC_MEASUREMENT = "da_DK.UTF-8";
    LC_MONETARY = "da_DK.UTF-8";
    LC_NAME = "da_DK.UTF-8";
    LC_NUMERIC = "da_DK.UTF-8";
    LC_PAPER = "da_DK.UTF-8";
    LC_TELEPHONE = "da_DK.UTF-8";
    LC_TIME = "da_DK.UTF-8";
  };

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  users.users.fbb = {
    isNormalUser = true;
    description = "Frederik Bosch";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    packages = with pkgs; [ ];
  };

  services.getty.autologinUser = "fbb";
  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };


  services.flatpak.enable = true;
  environment.systemPackages = with pkgs; [
    vim # fallback editor for root
    neovim
    nodejs
    fnm
    wget # essential download tool
    git # system-level git operations
    curl
    clang
    zig
    gcc
    cmake
    gnumake
    ripgrep
    jq
    fd
    tree
    unzip
    uutils-coreutils
    killall
    gparted
    parted
    nixfmt-rfc-style
    # mold
    # wineWowPackages.stable
    # wineWowPackages.fonts
    # wineWowPackages.waylandFull
    # winetricks
  ];


  fonts.fontconfig.enable = true;
  fonts.fontDir.enable = true;
  fonts.packages = with pkgs; [
    nerd-fonts.symbols-only
    nerd-fonts.jetbrains-mono
    font-awesome
  ];
  

}
