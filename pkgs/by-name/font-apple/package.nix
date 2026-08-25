{ pkgs }:

pkgs.stdenvNoCC.mkDerivation {
  pname = "font-apple";
  version = "26.2.1";

  dontUnpack = true;

  installPhase =
    let
      fonts = {
        "AppleColorEmoji.ttf" = {
          url = "https://github.com/samuelngs/apple-emoji-linux/releases/download/v18.4/AppleColorEmoji.ttf";
          hash = "sha256-pP0He9EUN7SUDYzwj0CE4e39SuNZ+SVz7FdmUviF6r0=";
        };
        "SF-Pro-Display-Regular.otf" = {
          url = "https://raw.githubusercontent.com/sahibjotsaggu/San-Francisco-Pro-Fonts/master/SF-Pro-Display-Regular.otf";
          hash = "sha256-fcBKwRAA91nJc6RcYQniwWQ3LbDbI91HlsiH33MEjNA=";
        };
        "SF-Pro-Text-Regular.otf" = {
          url = "https://raw.githubusercontent.com/sahibjotsaggu/San-Francisco-Pro-Fonts/master/SF-Pro-Text-Regular.otf";
          hash = "sha256-Ov0qyVxb/487oy8NZYZACUdnRznYV+c/TXtjlLCui3c=";
        };
        "SF-Pro-Rounded-Regular.otf" = {
          url = "https://raw.githubusercontent.com/sahibjotsaggu/San-Francisco-Pro-Fonts/master/SF-Pro-Rounded-Regular.otf";
          hash = "sha256-law3sWLJMN9jjLnLFJw2+HHL8fQpZsyYuA63/uGtyW4=";
        };
        "SF-Pro-Rounded-Medium.otf" = {
          url = "https://raw.githubusercontent.com/sahibjotsaggu/San-Francisco-Pro-Fonts/master/SF-Pro-Rounded-Medium.otf";
          hash = "sha256-pTyu3elDUk/6ImW24eJNJ3t2kSMPfYB1XLQZ167yj70=";
        };
        "SF-Pro-Rounded-Semibold.otf" = {
          url = "https://raw.githubusercontent.com/sahibjotsaggu/San-Francisco-Pro-Fonts/master/SF-Pro-Rounded-Semibold.otf";
          hash = "sha256-iqm39XBGVQ78JzkPNOnYjn+SUz6jpC0v9pv4UuHl1Oc=";
        };
        "SF-Pro-Rounded-Bold.otf" = {
          url = "https://raw.githubusercontent.com/sahibjotsaggu/San-Francisco-Pro-Fonts/master/SF-Pro-Rounded-Bold.otf";
          hash = "sha256-eLDNVmeashZbIpUiPWUZq84TnbB5VJO/Y3b23ZtQBBs=";
        };
        "SF-Mono-Regular.otf" = {
          url = "https://raw.githubusercontent.com/supercomputra/SF-Mono-Font/master/SFMono-Regular.otf";
          hash = "sha256-QeZ8ae4LtKNkqYX+TaBLdhSKkG2Zj0EaDE+nnO+esI4=";
        };
      };
      sources = pkgs.lib.mapAttrs (_: source: pkgs.fetchurl source) fonts;
    in
    pkgs.lib.concatLines (
      pkgs.lib.mapAttrsToList
        (
          name: source: ''install -Dm644 ${source} "$out/share/fonts/truetype/${name}"''
        )
        sources
    );

  meta = with pkgs.lib; {
    description = "Apple Color Emoji and San Francisco fonts";
    homepage = "https://developer.apple.com/fonts/";
    license = licenses.unfree;
    platforms = platforms.linux;
  };
}
