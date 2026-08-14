{ pkgs }:

pkgs.stdenvNoCC.mkDerivation {
  pname = "font-microsoft";
  version = "unstable";

  dontUnpack = true;

  installPhase =
    let
      segoeFluentIcons = pkgs.fetchzip {
        url = "https://download.microsoft.com/download/8/f/c/8fc7cbc3-177e-4a22-af48-2a85e1c5bffb/Segoe-Fluent-Icons.zip";
        hash = "sha256-MgwkgbVN8vZdZAFwG+CVYu5igkzNcg4DKLInOL1ES9A=";
        stripRoot = false;
      };
      tahoma = pkgs.fetchurl {
        url = "https://gitlab.winehq.org/wine/wine/-/raw/master/fonts/tahoma.ttf?ref_type=heads&inline=false";
        hash = "sha256-kPGrrU2gzgPaXSJ37nWpYAzoEtN8kOq3bgg4/6eTflU=";
      };
    in
    ''
      install -Dm644 "${segoeFluentIcons}/Segoe Fluent Icons.ttf" "$out/share/fonts/truetype/segmdl2.ttf"
      install -Dm644 ${tahoma} "$out/share/fonts/truetype/tahoma.ttf"
    '';

  meta = with pkgs.lib; {
    description = "Segoe Fluent Icons and Tahoma fonts";
    homepage = "https://learn.microsoft.com/windows/apps/design/downloads/";
    license = licenses.unfree;
    platforms = platforms.all;
  };
}
