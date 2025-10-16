{ pkgs, lib, ... }:

let
  mkTheme = { 
    url, 
    name, 
    description,
    homepage ? null,
    sha256 ? lib.fakeSha256,
    stripRoot ? false
  }: pkgs.stdenv.mkDerivation {
    pname = name;
    
    src = pkgs.fetchzip {
      inherit url sha256 stripRoot;
    };
    
    dontBuild = true;
    dontConfigure = true;
    
    installPhase = ''
      mkdir -p $out/share/themes
      cp -r . $out/share/themes/${name}
    '';
    
    meta = with lib; {
      inherit description;
      platforms = platforms.linux;
    } // lib.optionalAttrs (homepage != null) { inherit homepage; };
  };

  mono-gtk-theme = mkTheme {
    url = "https://github.com/witalihirsch/Mono-gtk-theme/releases/download/1.3/MonoTheme.zip";
    name = "MonoTheme-1.3";
    description = "Mono GTK theme - Light variant";
    homepage = "https://github.com/witalihirsch/Mono-gtk-theme";
  };

  mono-gtk-theme-dark = mkTheme {
    url = "https://github.com/witalihirsch/Mono-gtk-theme/releases/download/1.3/MonoTheme-dark.zip";
    name = "MonoTheme-dark-1.3";
    description = "Mono GTK theme - Dark variant";
    homepage = "https://github.com/witalihirsch/Mono-gtk-theme";
  };
in
{
  home.packages = [ 
    mono-gtk-theme 
    mono-gtk-theme-dark
  ];
  
  gtk = {
    enable = true;
    theme = {
      name = "MonoTheme-1.3";
      package = mono-gtk-theme;
    };
  };
}

