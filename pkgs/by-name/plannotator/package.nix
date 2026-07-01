{ lib
, stdenvNoCC
, fetchurl
,
}:

let
  pname = "plannotator";
  version = "0.21.4";

  inherit (stdenvNoCC.hostPlatform) system;
  platformSuffix =
    {
      x86_64-linux = "linux-x64";
      aarch64-linux = "linux-arm64";
      x86_64-darwin = "darwin-x64";
      aarch64-darwin = "darwin-arm64";
    }.${system} or (throw "${pname} is not available for ${system}");

  src = fetchurl {
    url = "https://github.com/backnotprop/plannotator/releases/download/v${version}/${pname}-${platformSuffix}";
    hash =
      {
        aarch64-darwin = "sha256-6nnXH/flF9M8d6zzu0bksHAgYdOKjCBiaC8bQIncWOE=";
        x86_64-darwin = "sha256-cuo16PP/rFBLTGsJUcGb9+bZhr/U4cqXRZeUD3JZoGw=";
        aarch64-linux = "sha256-eA+OqftZ77OGIUCag97ZY2a88VqaVex7Tr69kMirHUQ=";
        x86_64-linux = "sha256-sC2vwE3XP+HWoBufIiVMcgTwqGZrdJDVpCpl1dKQYO4=";
      }.${system};
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version src;

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/plannotator"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Interactive plan and code review tool for coding agents";
    homepage = "https://github.com/backnotprop/plannotator";
    changelog = "https://github.com/backnotprop/plannotator/releases/tag/v${version}";
    license = [
      licenses.mit
      licenses.asl20
    ];
    mainProgram = "plannotator";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = [ ];
  };
}
