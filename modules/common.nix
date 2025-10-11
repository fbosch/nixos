{ config, pkgs, ... }:

let
  zenbones-mono = pkgs.fetchzip {
    url = "https://github.com/zenbones-theme/zenbones-mono/releases/download/v2.400/Zenbones-Brainy-TTF.zip";
    sha256 = "sha256-Wrn9BYNs0Z9BDau60u2eX/LleXzcH1MuIJph6XfIRTE=";
    stripRoot = false;
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

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  fonts.packages = with pkgs; [
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
    vim
    neovim
    wget
    git
    delta
    ripgrep
    fish
    zoxide
    eza
    fd
    fzf
    lf
    bat
  ];

  system.activationScripts.bat-cache = {
    deps = [ "users" ];
    text = ''
      echo "Building bat cache..."
      ${pkgs.bat}/bin/bat cache --build 2>/dev/null || true
    '';
  };
}

