{ lib
, stdenv
, stdenvNoCC
, autoPatchelfHook
, fetchurl
,
}:

let
  pname = "vite-plus";
  version = "0.1.11";

  inherit (stdenvNoCC.hostPlatform) system;
  platformSuffix =
    {
      x86_64-linux = "linux-x64-gnu";
      aarch64-linux = "linux-arm64-gnu";
    }.${system} or (throw "${pname} is not available for ${system}");

  src = fetchurl {
    url = "https://registry.npmjs.org/@voidzero-dev/vite-plus-cli-${platformSuffix}/-/vite-plus-cli-${platformSuffix}-${version}.tgz";
    hash =
      {
        x86_64-linux = "sha256-Wh4T4F29p9zlC3m+JM25V/7WxdcUDACuuX54xFu44OI=";
        aarch64-linux = "sha256-VokaXEf/5ZygczMI8P2c6LdZM7fHZVSnyJWY/4LOiCY=";
      }.${system};
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 vp $out/bin/vp

    runHook postInstall
  '';

  meta = with lib; {
    description = "Unified web development toolchain CLI";
    homepage = "https://github.com/voidzero-dev/vite-plus";
    changelog = "https://github.com/voidzero-dev/vite-plus/releases/tag/v${version}";
    license = licenses.mit;
    mainProgram = "vp";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = [ ];
  };
}
