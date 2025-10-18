{ pkgs, ... }:
{
  home.file = {
    ".local/share/fonts/zenbones-mono".source = pkgs.fetchzip {
      url = "https://github.com/zenbones-theme/zenbones-mono/releases/download/v2.400/Zenbones-Brainy-TTF.zip";
      sha256 = "sha256-Wrn9BYNs0Z9BDau60u2eX/LleXzcH1MuIJph6XfIRTE=";
      stripRoot = false;
    };
    
    ".local/share/fonts/BabelStoneRunicElderFuthark.ttf".source = pkgs.fetchurl {
      url = "https://babelstone.co.uk/Fonts/Download/BabelStoneRunicElderFuthark.ttf";
      sha256 = "sha256-awYvgb6O07ouxwqg2OgomDia1j4jmVFwyAr7oSacNws=";
    };
    
    ".local/share/fonts/tahoma.ttf".source = pkgs.fetchurl {
      url = "https://gitlab.winehq.org/wine/wine/-/raw/master/fonts/tahoma.ttf?ref_type=heads&inline=false";
      sha256 = "sha256-kPGrrU2gzgPaXSJ37nWpYAzoEtN8kOq3bgg4/6eTflU=";
    };
    
    ".local/share/fonts/AppleColorEmoji.ttf".source = pkgs.fetchurl {
      url = "https://github.com/samuelngs/apple-emoji-linux/releases/download/v18.4/AppleColorEmoji.ttf";
      sha256 = "sha256-pP0He9EUN7SUDYzwj0CE4e39SuNZ+SVz7FdmUviF6r0=";
    };
    
    ".local/share/fonts/Phosphor-Fill.ttf".source = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/phosphor-icons/web/master/src/fill/Phosphor-Fill.ttf";
      sha256 = "sha256-x90bxwqKW5MfVTDliiBGeh515xwhigS4BGZkgzejHWs=";
    };
  };
}
