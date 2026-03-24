{ pkgs }:

pkgs.stdenvNoCC.mkDerivation {
  pname = "font-fast-font";
  version = "unstable-2026-02-25";

  src = pkgs.fetchFromGitHub {
    owner = "Born2Root";
    repo = "Fast-Font";
    rev = "21f7b0556d36f03db7415efe1702d2ec38da76ba";
    hash = "sha256-oU7cNO0p2yGN5WJs8HCzQXGil6az3cuz4aYeeCnqqk4=";
  };

  installPhase = ''
    install -dm755 "$out/share/fonts/truetype"
    find fast-fonts -type f -name '*.ttf' -exec install -Dm644 {} "$out/share/fonts/truetype/" \;
  '';

  meta = with pkgs.lib; {
    description = "Speed-reading font with bold fixation points for faster reading";
    homepage = "https://github.com/Born2Root/Fast-Font";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
