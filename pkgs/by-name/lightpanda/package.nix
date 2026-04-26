{ lib
, stdenvNoCC
, fetchurl
, autoPatchelfHook
,
}:

let
  pname = "lightpanda";
  version = "0.2.9";

  inherit (stdenvNoCC.hostPlatform) system;
  sources = {
    x86_64-linux = {
      url = "https://github.com/lightpanda-io/browser/releases/download/${version}/lightpanda-x86_64-linux";
      hash = "sha256-VL65btP2Ob7MT9JjproKabYOXn4D72/lDZxjR6PqOV0=";
    };
    aarch64-linux = {
      url = "https://github.com/lightpanda-io/browser/releases/download/${version}/lightpanda-aarch64-linux";
      hash = "sha256-n1TyzDGw2t2Ge6BuzOWfiqWfeHY5R5jpeIKupoC1rRk=";
    };
  };
  source = sources.${system} or (throw "Unsupported platform: ${system}");
in
stdenvNoCC.mkDerivation {
  inherit pname version;

  src = fetchurl {
    inherit (source) url hash;
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/lightpanda"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Headless browser built for AI agents and automation";
    homepage = "https://github.com/lightpanda-io/browser";
    changelog = "https://github.com/lightpanda-io/browser/releases/tag/${version}";
    license = licenses.agpl3Only;
    mainProgram = "lightpanda";
    platforms = builtins.attrNames sources;
    maintainers = [ ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
