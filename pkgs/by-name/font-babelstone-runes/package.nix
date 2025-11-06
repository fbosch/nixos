{ pkgs }:

pkgs.stdenvNoCC.mkDerivation {
  pname = "font-babelstone-runes";
  version = "unstable-2024-01-01";

  src = pkgs.fetchurl {
    url = "https://babelstone.co.uk/Fonts/Download/BabelStoneRunicElderFuthark.ttf";
    hash = "sha256-awYvgb6O07ouxwqg2OgomDia1j4jmVFwyAr7oSacNws=";
  };

  dontUnpack = true;

  installPhase = ''
    install -dm755 "$out/share/fonts/truetype"
    install -Dm644 "$src" "$out/share/fonts/truetype/BabelStoneRunicElderFuthark.ttf"
  '';

  meta = with pkgs.lib; {
    description = "BabelStone Runic Elder Futhark TrueType font";
    homepage = "https://www.babelstone.co.uk/Fonts/Runic.html";
    license = {
      shortName = "babelstone-freeware";
      fullName = "BabelStone Freeware Fonts Licence";
      url = "https://www.babelstone.co.uk/Fonts/License.html";
      free = true;
      redistributable = true;
    };
    platforms = platforms.all;
  };
}
