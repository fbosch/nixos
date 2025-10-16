{ config, pkgs, ... }:
let
  zenbones-mono = pkgs.fetchzip {
    url = "https://github.com/zenbones-theme/zenbones-mono/releases/download/v2.400/Zenbones-Brainy-TTF.zip";
    sha256 = "sha256-Wrn9BYNs0Z9BDau60u2eX/LleXzcH1MuIJph6XfIRTE=";
    stripRoot = false;
  };
  babelstone-elder-futhark = pkgs.fetchurl {
    url = "https://babelstone.co.uk/Fonts/Download/BabelStoneRunicElderFuthark.ttf";
    sha256 = "sha256-awYvgb6O07ouxwqg2OgomDia1j4jmVFwyAr7oSacNws=";
  };
  tahoma = pkgs.fetchurl {
    url = "https://gitlab.winehq.org/wine/wine/-/raw/master/fonts/tahoma.ttf?ref_type=heads&inline=false";
    sha256 = "sha256-kPGrrU2gzgPaXSJ37nWpYAzoEtN8kOq3bgg4/6eTflU=";
  };
  apple-emojis = pkgs.fetchurl {
    url = "https://github.com/samuelngs/apple-emoji-linux/releases/download/v18.4/AppleColorEmoji.ttf";
    sha256 = "sha256-pP0He9EUN7SUDYzwj0CE4e39SuNZ+SVz7FdmUviF6r0=";
  };
in
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


  fonts.fontDir.enable = true;
  fonts.packages = with pkgs; [
    nerd-fonts.symbols-only
    nerd-fonts.jetbrains-mono
    font-awesome
    (pkgs.stdenv.mkDerivation {
      name = "zenbones-mono";
      src = zenbones-mono;
      installPhase = ''
        mkdir -p $out/share/fonts/truetype
        find $src -name '*.ttf' -exec cp {} $out/share/fonts/truetype \;
        find $src -name '*.otf' -exec cp {} $out/share/fonts/truetype \;
      '';
    })
    (pkgs.stdenv.mkDerivation {
      name = "babelstone-elder-futhark";
      src = babelstone-elder-futhark;
      dontUnpack = true;
      installPhase = ''
        mkdir -p $out/share/fonts/truetype
        cp $src $out/share/fonts/truetype/BabelStoneRunicElderFuthark.ttf
      '';
    })
    (pkgs.stdenv.mkDerivation {
      name = "tahoma";
      src = tahoma;
      dontUnpack = true;
      installPhase = ''
        mkdir -p $out/share/fonts/truetype
        cp $src $out/share/fonts/truetype/tahoma.ttf
      '';
    })
    (pkgs.stdenv.mkDerivation {
      name = "apple-color-emoji";
      src = apple-emojis;
      dontUnpack = true;
      installPhase = ''
        mkdir -p $out/share/fonts/truetype
        cp $src $out/share/fonts/truetype/AppleColorEmoji.ttf
      '';
    })
  ];

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
    # wineWowPackages.stable
    # wineWowPackages.fonts
    # wineWowPackages.waylandFull
    # winetricks
  ];

  services.flatpak.enable = true;

}
