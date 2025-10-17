{ lib, pkgs, ... }:

let
  mkFont = {
    src,
    name,
    description,
    installPhase ? null
  }:
  let
    font = pkgs.stdenv.mkDerivation {
      inherit name src;
      
      dontBuild = true;
      dontConfigure = true;
      
      installPhase = if installPhase != null then installPhase else ''
        runHook preInstall
        
        mkdir -p $out/share/fonts
        find $src -name '*.ttf' -exec cp {} $out/share/fonts \;
        find $src -name '*.otf' -exec cp {} $out/share/fonts \;
        
        runHook postInstall
      '';
      
      meta = with lib; {
        inherit description;
        platforms = platforms.linux;
      };
    };
  in {
    derivation = font;
    homeFile = {
      ".local/share/fonts/${name}".source = "${font}/share/fonts";
    };
  };

  mkFontFromZip = {
    url,
    name,
    description,
    sha256 ? lib.fakeSha256,
    stripRoot ? true,
    installPhase ? null
  }:
    mkFont {
      inherit name description installPhase;
      src = pkgs.fetchzip {
        inherit url sha256 stripRoot;
      };
    };

  mkFontFromUrl = {
    url,
    name,
    fileName,
    description,
    sha256 ? lib.fakeSha256
  }:
    mkFont {
      inherit name description;
      src = pkgs.fetchurl {
        inherit url sha256;
      };
      installPhase = ''
        runHook preInstall
        
        mkdir -p $out/share/fonts
        cp $src $out/share/fonts/${fileName}
        
        runHook postInstall
      '';
    };

  fonts = [
    (mkFontFromZip {
      url = "https://github.com/zenbones-theme/zenbones-mono/releases/download/v2.400/Zenbones-Brainy-TTF.zip";
      name = "zenbones-mono";
      description = "Zenbones Mono font family";
      sha256 = "sha256-Wrn9BYNs0Z9BDau60u2eX/LleXzcH1MuIJph6XfIRTE=";
      stripRoot = false;
    })
    (mkFontFromUrl {
      url = "https://babelstone.co.uk/Fonts/Download/BabelStoneRunicElderFuthark.ttf";
      name = "babelstone-elder-futhark";
      fileName = "BabelStoneRunicElderFuthark.ttf";
      description = "BabelStone Runic Elder Futhark font";
      sha256 = "sha256-awYvgb6O07ouxwqg2OgomDia1j4jmVFwyAr7oSacNws=";
    })
    (mkFontFromUrl {
      url = "https://gitlab.winehq.org/wine/wine/-/raw/master/fonts/tahoma.ttf?ref_type=heads&inline=false";
      name = "tahoma";
      fileName = "tahoma.ttf";
      description = "Tahoma font";
      sha256 = "sha256-kPGrrU2gzgPaXSJ37nWpYAzoEtN8kOq3bgg4/6eTflU=";
    })
    (mkFontFromUrl {
      url = "https://github.com/samuelngs/apple-emoji-linux/releases/download/v18.4/AppleColorEmoji.ttf";
      name = "apple-color-emoji";
      fileName = "AppleColorEmoji.ttf";
      description = "Apple Color Emoji font";
      sha256 = "sha256-pP0He9EUN7SUDYzwj0CE4e39SuNZ+SVz7FdmUviF6r0=";
    })
    (mkFontFromUrl {
      url = "https://github.com/phosphor-icons/web/blob/master/src/fill/Phosphor-Fill.ttf";
      name = "phosphor-fill";
      fileName = "Phosphor-Fill.ttf";
      description = "Phosphor Fill icon font";
      sha256 = "sha256-x90bxwqKW5MfVTDliiBGeh515xwhigS4BGZkgzejHWs=";
    })
  ];
  
  fontHomeFiles = lib.mkMerge (map (f: f.homeFile) fonts);
in
{
  fonts.fontconfig.enable = true;
  
  fonts.packages = with pkgs; [
    nerd-fonts.symbols-only
    nerd-fonts.jetbrains-mono
    font-awesome
  ];
  
  home.file = fontHomeFiles;
}