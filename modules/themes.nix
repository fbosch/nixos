{ pkgs, lib, ... }:

let
  mono-gtk-theme = pkgs.stdenv.mkDerivation {
    pname = "mono-gtk-theme";
    version = "1.3";
    
    src = pkgs.fetchurl {
      url = "https://github.com/witalihirsch/Mono-gtk-theme/releases/download/1.3/MonoTheme.tar.xz";
      sha256 = "sha256-QGJgaKf+ODG49+31p6jySvK0gGdgm2/9flhebvjOC78=";
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

