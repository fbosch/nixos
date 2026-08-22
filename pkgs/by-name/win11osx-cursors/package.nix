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

  nativeBuildInputs = [ pkgs.unzip ];

  installPhase = ''
    runHook preInstall

    unzip -q "$src" -d "$TMPDIR/win11osx"
    install -d "$out/share/icons/Win11OSX"
    cp -a "$TMPDIR/win11osx/Win11OSX/Win11OSX/." "$out/share/icons/Win11OSX/"

    runHook postInstall
  '';

  meta = with pkgs.lib; {
    description = "Windows 11 and macOS-inspired XCursor theme";
    homepage = "https://store.kde.org/p/2334253/";
    license = licenses.unfree;
    platforms = platforms.linux;
  };
}
