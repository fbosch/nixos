{ fetchurl
, lib
, stdenvNoCC
,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "rpgm-decrypt";
  version = "0.3.17";

  src = fetchurl {
    url = "https://github.com/rolanfreeman6-png/rpgm-decrypt/releases/download/v${finalAttrs.version}-gui1.0.0/rpgm-decrypt-linux-x64";
    hash = "sha256-9Es2b4xej3bOcWpS6yptaIVPnFrXEQFET0EFLW1V0W0=";
  };

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/rpgm-decrypt"
    runHook postInstall
  '';

  meta = {
    description = "CLI for decrypting RPG Maker XP, VX, VX Ace, MV, and MZ games";
    homepage = "https://github.com/rolanfreeman6-png/rpgm-decrypt";
    changelog = "https://github.com/rolanfreeman6-png/rpgm-decrypt/releases/tag/v${finalAttrs.version}-gui1.0.0";
    license = lib.licenses.asl20;
    mainProgram = "rpgm-decrypt";
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
