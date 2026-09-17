{ autoPatchelfHook
, fetchurl
, lib
, stdenvNoCC
,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "rpgmasd";
  version = "3.2.2";

  src = fetchurl {
    url = "https://github.com/RPG-Maker-Translation-Tools/rpgm-asset-decrypter-rs/releases/download/v${finalAttrs.version}/rpgmasd";
    hash = "sha256-sIAjowztvpPyXOO1VOEYTa/EmaatQ27DIN/FeNVA3R0=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/rpgmasd"
    runHook postInstall
  '';

  meta = {
    description = "CLI for decrypting RPG Maker MV and MZ image and audio assets";
    homepage = "https://github.com/RPG-Maker-Translation-Tools/rpgm-asset-decrypter-rs";
    changelog = "https://github.com/RPG-Maker-Translation-Tools/rpgm-asset-decrypter-rs/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.wtfpl;
    mainProgram = "rpgmasd";
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
