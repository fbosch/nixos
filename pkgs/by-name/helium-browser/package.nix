{ lib
, fetchurl
, appimageTools
, makeWrapper
,
}:

let
  pname = "helium-browser";
  version = "0.10.5.1";

  src = fetchurl {
    url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-x86_64.AppImage";
    hash = "sha256-c/ea8C1XjTkBo0/ujGHEbKWyCmRMxyuiuOzAO9AMf1o=";
  };

  icon = fetchurl {
    url = "https://github.com/imputnet/helium/raw/main/resources/branding/app_icon/raw.png";
    hash = "sha256-dX8As09QbMdBlDf2KVHa10GecnCumWWPe1VLo6Ofnt0=";
  };

  appimageContents = appimageTools.extractType2 { inherit pname version src; };
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

    install -Dm444 ${icon} \
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
