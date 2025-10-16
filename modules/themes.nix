{ pkgs, lib, ... }:

let
  mkTheme = { 
    url, 
    name, 
    description,
    homepage ? null,
    sha256 ? lib.fakeSha256,
    stripRoot ? false
  }: 
  let
    theme = pkgs.stdenv.mkDerivation {
      name = name;
      
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
  in {
    derivation = theme;
    homeFile = {
      ".themes/${name}".source = "${theme}/share/themes/${name}";
    };
  };

  themes = [
    (mkTheme {
      url = "https://github.com/witalihirsch/Mono-gtk-theme/releases/download/1.3/MonoTheme.zip";
      name = "MonoTheme-1.3";
      description = "Mono GTK theme - Light variant";
      homepage = "https://github.com/witalihirsch/Mono-gtk-theme";
    })
    (mkTheme {
      url = "https://github.com/witalihirsch/Mono-gtk-theme/releases/download/1.3/MonoTheme-dark.zip";
      name = "MonoTheme-dark-1.3";
      description = "Mono GTK theme - Dark variant";
      homepage = "https://github.com/witalihirsch/Mono-gtk-theme";
    })
  ];

  themeHomeFiles = lib.mkMerge (map (t: t.homeFile) themes);
in
{
  gtk.enable = true;
  home.file = themeHomeFiles;
}
