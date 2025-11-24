{ lib
, fetchurl
, appimageTools
, makeWrapper
}:

let
  pname = "helium-browser";
  version = "0.6.7.1";

  src = fetchurl {
    url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-x86_64.AppImage";
    hash = "sha256-fZTBNhaDk5EeYcxZDJ83tweMZqtEhd7ws8AFUcHjFLs=";
  };

  appimageContents = appimageTools.extractType2 {
    inherit pname version src;
  };
in
appimageTools.wrapType2 rec {
  inherit pname version src;

  nativeBuildInputs = [ makeWrapper ];

  extraInstallCommands = ''
    wrapProgram "$out/bin/${pname}" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform=wayland --enable-features=WaylandWindowDecorations,UseOzonePlatform --enable-wayland-ime=true}}"

    install -Dm444 ${appimageContents}/helium.desktop $out/share/applications/${pname}.desktop

    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace 'Exec=AppRun %U' 'Exec=${pname} %U' \
      --replace 'Exec=AppRun' 'Exec=${pname}' \

    install -Dm444 ${appimageContents}/usr/share/icons/hicolor/256x256/apps/helium.png \
      $out/share/icons/hicolor/256x256/apps/helium.png
  '';

  extraPkgs = pkgs: with pkgs; [ nss_latest ];

  meta = with lib; {
    description = "A privacy-focused Chromium-based browser";
    homepage = "https://helium.computer/";
    license = licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
    maintainers = [ ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
