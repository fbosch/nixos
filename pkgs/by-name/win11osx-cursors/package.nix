{ pkgs }:

let
  src = pkgs.fetchurl {
    url = "https://api.kde-look.org/ocs/v1/content/data/2334253";
    name = "Win11OSX.zip";
    hash = "sha256-1GpPXlV66NO5tlZw1JE4NqgZMt/0XTWUYNGZE8tIMpI=";
    downloadToTemp = true;

    postFetch = ''
      downloadUrl="$(${pkgs.lib.getExe' pkgs.libxml2 "xmllint"} \
        --xpath 'string(//content/downloadlink1)' \
        "$downloadedFile")"

      if [ -z "$downloadUrl" ]; then
        echo "OCS response did not contain downloadlink1" >&2
        exit 1
      fi

      ${pkgs.lib.getExe' pkgs.curl "curl"} \
        --fail \
        --location \
        --retry 3 \
        --retry-all-errors \
        --connect-timeout 15 \
        --max-time 120 \
        --cacert ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
        "$downloadUrl" \
        --output "$out"
    '';
  };
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "win11osx-cursors";
  version = "1.1";

  inherit src;
  dontUnpack = true;

  nativeBuildInputs = [
    pkgs.unzip
    pkgs.xcur2png
    pkgs.imagemagick
    pkgs.xcursorgen
  ];

  installPhase = ''
    runHook preInstall

    unzip -q "$src" -d "$TMPDIR/win11osx"
    install -d "$out/share/icons/Win11OSX"
    cp -a "$TMPDIR/win11osx/Win11OSX/Win11OSX/." "$out/share/icons/Win11OSX/"

    # Upstream provides no 24 px frames, so 24 px requests select 32 px instead.
    for cursor in "$out/share/icons/Win11OSX/cursors/"*; do
      [ -L "$cursor" ] && continue

      cursorName="$(basename "$cursor")"
      cursorDir="$TMPDIR/cursors/$cursorName"
      install -d "$cursorDir/images"
      xcur2png -q -c "$cursorDir/original.conf" -d "$cursorDir/images" "$cursor"

      minSize="$(awk 'NR == 2 || $1 < min { min = $1 } END { print min }' "$cursorDir/original.conf")"
      [ "$minSize" -le 24 ] && continue

      while read -r size xhot yhot image delay; do
        [ "$size" = "#size" ] && continue
        [ "$size" = "$minSize" ] || continue

        scaledImage="$cursorDir/images/24-$(basename "$image")"
        magick "$image" -resize 24x24 "$scaledImage"
        printf '24\t%s\t%s\t%s\t%s\n' \
          "$((xhot * 24 / minSize))" \
          "$((yhot * 24 / minSize))" \
          "$scaledImage" \
          "$delay" \
          >> "$cursorDir/scaled.conf"
      done < "$cursorDir/original.conf"

      tail -n +2 "$cursorDir/original.conf" >> "$cursorDir/scaled.conf"
      xcursorgen "$cursorDir/scaled.conf" "$cursor"
    done

    runHook postInstall
  '';

  meta = with pkgs.lib; {
    description = "Windows 11 and macOS-inspired XCursor theme";
    homepage = "https://store.kde.org/p/2334253/";
    license = licenses.unfree;
    platforms = platforms.linux;
  };
}
