{ pkgs, ... }:

let
  mono-gtk-theme = pkgs.stdenv.mkDerivation {
    pname = "mono-gtk-theme";
    version = "1.3";
    
    src = pkgs.fetchurl {
      url = "https://github.com/witalihirsch/Mono-gtk-theme/releases/download/1.3/MonoTheme-1.3.tar.gz";
      sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };
    
    installPhase = ''
      mkdir -p $out/share/themes
      cp -r MonoTheme-1.3 $out/share/themes/
    '';
    
    meta = with pkgs.lib; {
      description = "Mono GTK theme";
      homepage = "https://github.com/witalihirsch/Mono-gtk-theme";
      platforms = platforms.linux;
    };
  };
in
{
  home.packages = [ mono-gtk-theme ];
  
  gtk = {
    enable = true;
    theme = {
      name = "MonoTheme-1.3";
      package = mono-gtk-theme;
    };
  };
}

