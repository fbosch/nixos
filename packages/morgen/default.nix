{ lib
, fetchurl
, appimageTools
, makeWrapper
}:

let
  pname = "morgen";
  version = "4.0.0-beta.27";

  src = fetchurl {
    url = "https://dl.todesktop.com/210203cqcj00tw1/builds/251017qgr8g4epn/linux/appImage/x64";
    hash = "sha256-jSgI7dgSNKWqdFDVXjghUa5hStjX1gpgV/oxd8bC9dA=";
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
      --set-default ELECTRON_OZONE_PLATFORM_HINT auto \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform=wayland --enable-features=WaylandWindowDecorations,UseOzonePlatform --enable-wayland-ime=true}}"

    install -Dm444 ${appimageContents}/morgen.desktop $out/share/applications/${pname}.desktop

    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace 'Exec=AppRun %U' 'Exec=${pname} %U' \
      --replace 'Exec=AppRun' 'Exec=${pname}' \

    for size in 16 32 48 64 128 256 512 1024; do
      icon="${appimageContents}/usr/share/icons/hicolor/"$size"x"$size"/apps/morgen.png"
      if [ -f "$icon" ]; then
        install -Dm444 "$icon" "$out/share/icons/hicolor/"$size"x"$size"/apps/morgen.png"
      fi
    done

    if [ -f ${appimageContents}/morgen.png ]; then
      install -Dm444 ${appimageContents}/morgen.png $out/share/pixmaps/morgen.png
    fi
  '';

  extraPkgs = pkgs: with pkgs; [ nss_latest ];

  meta = with lib; {
    description = "A modern desktop calendar application";
    homepage = "https://morgen.so/";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
    maintainers = [ ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
