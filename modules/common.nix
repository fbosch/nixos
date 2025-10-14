{ config, pkgs, ... }:

let
  zenbones-mono = pkgs.fetchzip {
    url = "https://github.com/zenbones-theme/zenbones-mono/releases/download/v2.400/Zenbones-Brainy-TTF.zip";
    sha256 = "sha256-Wrn9BYNs0Z9BDau60u2eX/LleXzcH1MuIJph6XfIRTE=";
    stripRoot = false;
  };
  babelstone-elder-futhark = pkgs.fetchurl {
    url = "https://babelstone.co.uk/Fonts/Download/BabelStoneRunicElderFuthark.ttf";
    sha256 = "sha256-Wrn9BYNs0Z9BDau60u2eX/LleXzcH1MuIJph6XfIRTE=";
    striproot = false;
  };
in
{
  time.timeZone = "Europe/Copenhagen";

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
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [];
  };

  services.getty.autologinUser = "fbb";

  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    extra-substituters = ["https://walker.cachix.org"];
    trusted-public-keys = ["walker.cachix.org-1:fG8q+uAaMqhsMxWjwvk0IMb4mFPFLqHjuvfwQxE4oJM="];
  };

  fonts.packages = with pkgs; [
    nerd-fonts.symbols-only
    nerd-fonts.jetbrains-mono
    (pkgs.stdenv.mkDerivation {
      name = "zenbones-mono";
      src = zenbones-mono;
      installPhase = ''
        mkdir -p $out/share/fonts/truetype
        find $src -name '*.ttf' -exec cp {} $out/share/fonts/truetype \;
        find $src -name '*.otf' -exec cp {} $out/share/fonts/truetype \;
      '';
    })
  ];

  environment.systemPackages = with pkgs; [ 
    vim   # fallback editor for root
    neovim
    nodejs
    fnm
    wget  # essential download tool
    git   # system-level git operations
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
  ];

  services.flatpak.enable = true;

}

