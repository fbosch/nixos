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

      for requiredCursor in pointer link; do
        if [ ! -e "$cursors/$requiredCursor" ]; then
          echo "Vision cursor theme is missing $cursors/$requiredCursor" >&2
          exit 1
        fi
      done

      defaultTarget="$(readlink -f "$cursors/pointer")"
      linkTarget="$(readlink -f "$cursors/link")"

      if cmp -s "$defaultTarget" "$linkTarget"; then
        echo "Vision cursor pointer and link assets unexpectedly resolve to the same cursor" >&2
        exit 1
      fi

      # Upstream follows Windows naming: pointer is the default arrow and link
      # is the hand. Preserve the arrow before normalizing XCursor aliases.
      cp --dereference "$defaultTarget" "$cursors/.vision-default"
      cp --dereference "$linkTarget" "$cursors/.vision-pointer"

      # Keep aliases that previously resolved to the Windows-named pointer on
      # the default arrow after `pointer` gains Linux hand semantics.
      for cursor in "$cursors"/*; do
        if [ -L "$cursor" ] && [ "$(readlink -f "$cursor")" = "$defaultTarget" ]; then
          ln -sfn .vision-default "$cursor"
        fi
      done

      for cursorName in default arrow left_ptr; do
        if [ ! -e "$cursors/$cursorName" ]; then
          ln -s .vision-default "$cursors/$cursorName"
        fi
      done

      for cursorName in \
        pointer \
        hand \
        hand1 \
        hand2 \
        pointing_hand \
        9d800788f1b08800ae810202380a0822 \
        e29285e634086352946a0e7090d73106
      do
        rm -f "$cursors/$cursorName"
        ln -s .vision-pointer "$cursors/$cursorName"
      done

      rm -f "$cursors/link"
      ln -s .vision-pointer "$cursors/link"
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
