{ pkgs }:

pkgs.stdenvNoCC.mkDerivation {
  pname = "font-zenbones";
  version = "2.400";

  src = pkgs.fetchzip {
    url = "https://github.com/zenbones-theme/zenbones-mono/releases/download/v2.400/Zenbones-Brainy-TTF.zip";
    hash = "sha256-Wrn9BYNs0Z9BDau60u2eX/LleXzcH1MuIJph6XfIRTE=";
    stripRoot = false;
  };

  installPhase = ''
    install -dm755 "$out/share/fonts/truetype"
    find . -type f -name '*.ttf' -exec install -Dm644 {} "$out/share/fonts/truetype/" \;
  '';

  meta = with pkgs.lib; {
    description = "Zenbones Mono fonts (Brainy TTF)";
    homepage = "https://github.com/zenbones-theme/zenbones-mono";
    license = licenses.ofl;
    platforms = platforms.all;
  };
}
