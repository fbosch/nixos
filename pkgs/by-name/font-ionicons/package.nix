{ pkgs }:

pkgs.stdenvNoCC.mkDerivation {
  pname = "font-ionicons";
  version = "2.0.1";

  src = pkgs.fetchurl {
    url = "https://code.ionicframework.com/ionicons/2.0.1/fonts/ionicons.ttf";
    hash = "sha256-XnAINewFKTo9D541Tn0DgxnTRSHNJ554IZjf9tHdWPI=";
  };

  dontUnpack = true;

  installPhase = ''
    install -dm755 "$out/share/fonts/truetype"
    install -Dm644 "$src" "$out/share/fonts/truetype/ionicons.ttf"
  '';

  meta = with pkgs.lib; {
    description = "Ionicons 2.0.1 TrueType font";
    homepage = "https://ionicons.com/";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
