{ pkgs, lib, ... }:

let
  mono-gtk-theme = pkgs.stdenv.mkDerivation rec {
    pname = "mono-gtk-theme";
    version = "1.3";

    src = pkgs.fetchzip {
      url = "https://github.com/witalihirsch/Mono-gtk-theme/releases/download/${version}/MonoTheme.zip";
      sha256 = "sha256-/Ysak/WeWY4+svCu3yhi/blfcUsSnGOrWn8/YCyNTYM=";
      stripRoot = true;
    };

    dontBuild = true;
    dontConfigure = true;

    installPhase = ''
      	    mkdir -p $out/share/themes
      	    cp -r . $out/share/themes/MonoTheme-${version}
    '';

    meta = with lib; {
      description = "Mono GTK theme";
      homepage = "https://github.com/witalihirsch/Mono-gtk-theme";
      platforms = platforms.linux;
    };
  };
in
{
  home.packages = [ mono-gtk-theme ];

}
