{ pkgs }:

pkgs.stdenvNoCC.mkDerivation {
  pname = "font-apple";
  version = "26.2.1";

  dontUnpack = true;

  installPhase =
    let
      sfPro = pkgs.fetchFromGitHub {
        owner = "sahibjotsaggu";
        repo = "San-Francisco-Pro-Fonts";
        rev = "8bfea09aa6f1139479f80358b2e1e5c6dc991a58";
        hash = "sha256-mAXExj8n8gFHq19HfGy4UOJYKVGPYgarGd/04kUIqX4=";
      };
      fonts = {
        "AppleColorEmoji.ttf" = {
          url = "https://github.com/samuelngs/apple-emoji-linux/releases/download/v18.4/AppleColorEmoji.ttf";
          hash = "sha256-pP0He9EUN7SUDYzwj0CE4e39SuNZ+SVz7FdmUviF6r0=";
        };
        "SF-Mono-Regular.otf" = {
          url = "https://raw.githubusercontent.com/supercomputra/SF-Mono-Font/master/SFMono-Regular.otf";
          hash = "sha256-QeZ8ae4LtKNkqYX+TaBLdhSKkG2Zj0EaDE+nnO+esI4=";
        };
      };
      sources = pkgs.lib.mapAttrs (_: source: pkgs.fetchurl source) fonts;
    in
    ''
      install -dm755 "$out/share/fonts/truetype"

      for font in "${sfPro}"/*.otf "${sfPro}"/*.ttf; do
        install -Dm644 "$font" "$out/share/fonts/truetype/$(basename "$font")"
      done

      ${pkgs.lib.concatLines (
        pkgs.lib.mapAttrsToList (
          name: source: ''install -Dm644 ${source} "$out/share/fonts/truetype/${name}"''
        ) sources
      )}
    '';

  meta = with pkgs.lib; {
    description = "Apple Color Emoji, San Francisco Pro, and San Francisco Mono fonts";
    homepage = "https://developer.apple.com/fonts/";
    license = licenses.unfree;
    platforms = platforms.linux;
  };
}
