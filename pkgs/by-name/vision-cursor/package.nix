{ fetchurl
, lib
, stdenvNoCC
,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "vision-cursor";
  version = "1.0";

  srcs = [
    (fetchurl {
      url = "https://github.com/zDyant/Vision-Cursor/releases/download/v${finalAttrs.version}/Vision-Black-Linux.tar.gz";
      hash = "sha256-Mgz00DxJ4g6JCu5D1V/O507pJN9iEGw37SzFHAc9tVY=";
    })
    (fetchurl {
      url = "https://github.com/zDyant/Vision-Cursor/releases/download/v${finalAttrs.version}/Vision-White-Linux.tar.gz";
      hash = "sha256-IYwWAyiNjosGxC5vddvnfGwtVghWOoCl0hXqxVsKDh4=";
    })
  ];

  sourceRoot = ".";
  dontBuild = true;

  postPatch = ''
    for theme in Vision-Black Vision-White; do
      cursors="$theme/cursors"

      if [ ! -d "$cursors" ]; then
        echo "Vision cursor theme is missing $cursors" >&2
        exit 1
      fi

      pointerTarget=""
      for candidate in hand2 pointing_hand hand1 hand link; do
        if [ -e "$cursors/$candidate" ]; then
          pointerTarget="$(readlink -f "$cursors/$candidate")"
          break
        fi
      done

      if [ -z "$pointerTarget" ]; then
        echo "Vision cursor theme has no known clickable-pointer cursor" >&2
        exit 1
      fi

      # The Linux release already contains an XCursor theme, but not every
      # compatibility alias used by GTK/X11 applications. Preserve all
      # existing names and add only missing aliases to the existing hand.
      cp --dereference "$pointerTarget" "$cursors/.vision-pointer"

      for cursorName in \
        pointer \
        hand \
        hand1 \
        hand2 \
        pointing_hand \
        9d800788f1b08800ae810202380a0822 \
        e29285e634086352946a0e7090d73106
      do
        if [ ! -e "$cursors/$cursorName" ]; then
          ln -s .vision-pointer "$cursors/$cursorName"
        fi
      done
    done
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/icons
    cp -R Vision-Black Vision-White $out/share/icons/

    runHook postInstall
  '';

  meta = {
    description = "Minimalist cursor theme inspired by Windows 11";
    homepage = "https://github.com/zDyant/Vision-Cursor";
    downloadPage = "https://github.com/zDyant/Vision-Cursor/releases";
    license = lib.licenses.cc-by-nc-nd-40;
    maintainers = [ ];
    platforms = lib.platforms.linux;
  };
})
