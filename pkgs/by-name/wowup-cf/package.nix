{
  lib,
  appimageTools,
  fetchurl,
}:

let
  # Keep Forever fixes available until the pinned nixpkgs includes this release.
  pname = "wowup-cf";
  version = "2.24.1";
  src = fetchurl {
    url = "https://github.com/WowUp/WowUp.CF/releases/download/v${version}/WowUp-CF-${version}.AppImage";
    hash = "sha256-dK3fKTnS2jFAa3P0gI4WNjz8vbHaM7lOy+fBaD9vqxs=";
  };
  appimageContents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -m 444 -D ${appimageContents}/${pname}.desktop -t $out/share/applications
    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=${pname}'
    cp -r ${appimageContents}/usr/share/icons $out/share
  '';

  meta = {
    description = "World of Warcraft addon updater with CurseForge support";
    homepage = "https://wowup.io/";
    downloadPage = "https://github.com/WowUp/WowUp.CF/releases";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "wowup-cf";
    platforms = [ "x86_64-linux" ];
  };
}
