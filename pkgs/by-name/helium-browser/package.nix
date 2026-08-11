{ lib
, fetchurl
, appimageTools
, makeWrapper
, writeShellApplication
, coreutils
, jq
,
}:

let
  pname = "helium-browser";
  version = "0.14.9.1";

  src = fetchurl {
    url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-x86_64.AppImage";
    hash = "sha256-cuQiMGhOPjE7ixuZiFGpRuGF9SdVcNPYUXSXhjZBLKQ=";
  };

  icon = fetchurl {
    url = "https://github.com/imputnet/helium/raw/main/resources/branding/app_icon/raw.png";
    hash = "sha256-dX8As09QbMdBlDf2KVHa10GecnCumWWPe1VLo6Ofnt0=";
  };

  appimageContents = appimageTools.extract { inherit pname version src; };
  widevineSetup = writeShellApplication {
    name = "helium-widevine-setup";
    runtimeInputs = [
      coreutils
      jq
    ];
    text = builtins.readFile ./helium-widevine-setup.sh;
  };
in
appimageTools.wrapType2 rec {
  inherit pname version src;

  nativeBuildInputs = [ makeWrapper ];

  extraInstallCommands = ''
    wrapProgram "$out/bin/${pname}" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform=wayland --enable-features=WaylandWindowDecorations,UseOzonePlatform --enable-wayland-ime=true}}" \
      --add-flags --enable-gpu-rasterization \
      --add-flags --enable-zero-copy

    install -Dm444 ${appimageContents}/helium.desktop $out/share/applications/${pname}.desktop

    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace 'Exec=AppRun %U' 'Exec=${pname} %U' \
      --replace 'Exec=AppRun' 'Exec=${pname}' \
      --replace 'Exec=helium' 'Exec=${pname}' \
      --replace-fail 'Icon=helium' "Icon=$out/share/icons/hicolor/256x256/apps/helium.png" \

    install -Dm444 ${icon} \
      $out/share/icons/hicolor/256x256/apps/helium.png
  '';

  extraPkgs = pkgs: with pkgs; [ nss_latest ];

  passthru = {
    inherit widevineSetup;
  };

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
