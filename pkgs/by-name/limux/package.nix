{ lib
, fetchurl
, appimageTools
, nss_latest
,
}:

let
  pname = "limux";
  version = "0.1.13";

  src = fetchurl {
    url = "https://github.com/am-will/limux/releases/download/v${version}/Limux-${version}-x86_64.AppImage";
    hash = "sha256-y/QMnLWFPA2fDkp9/yCTyYkzoUjx3IAjNO9Rz6Ms3Hs=";
  };

  icon = fetchurl {
    url = "https://cmux.com/logo.png";
    hash = "sha256-hw9pprEMK4oVm4yK9jA7EaLm+OnUMx8G4BGDkOEhVjs=";
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraPkgs = pkgs: with pkgs; [ nss_latest ];

  extraInstallCommands = ''
    install -Dm444 ${icon} \
      $out/share/icons/hicolor/512x512/apps/${pname}.png

    mkdir -p $out/share/applications
    cat > $out/share/applications/${pname}.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=Limux
    Comment=GPU-accelerated terminal workspace manager
    Exec=${pname} %U
    Icon=${pname}
    Terminal=false
    Categories=System;TerminalEmulator;
    EOF
  '';

  meta = with lib; {
    description = "GPU-accelerated terminal workspace manager for Linux";
    homepage = "https://github.com/am-will/limux";
    changelog = "https://github.com/am-will/limux/releases/tag/v${version}";
    license = licenses.mit;
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
