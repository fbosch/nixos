{ pkgs, ... }:
{
  home.file = {
    ".local/share/fonts/zenbones-mono".source = pkgs.fetchzip {
      url = "https://github.com/zenbones-theme/zenbones-mono/releases/download/v2.400/Zenbones-Brainy-TTF.zip";
      sha256 = "sha256-Wrn9BYNs0Z9BDau60u2eX/LleXzcH1MuIJph6XfIRTE=";
      stripRoot = false;
    };
    
    ".local/share/fonts/segoe-fluent-icons".source = pkgs.fetchzip {
      url = "https://download.microsoft.com/download/8/f/c/8fc7cbc3-177e-4a22-af48-2a85e1c5bffb/Segoe-Fluent-Icons.zip";
      sha256 = "sha256-MgwkgbVN8vZdZAFwG+CVYu5igkzNcg4DKLInOL1ES9A=";
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
    
    ".local/share/fonts/ionicons.ttf".source = pkgs.fetchurl {
      url = "https://code.ionicframework.com/ionicons/2.0.1/fonts/ionicons.ttf";
      sha256 = "sha256-XnAINewFKTo9D541Tn0DgxnTRSHNJ554IZjf9tHdWPI=";
    };
  };
}
