{ lib
, stdenvNoCC
, fetchurl
,
}:

let
  pname = "code-on-incus";
  version = "0.7.0";

  inherit (stdenvNoCC.hostPlatform) system;
  asset =
    {
      x86_64-linux = "coi-linux-amd64";
      aarch64-linux = "coi-linux-arm64";
    }.${system} or (throw "${pname} is not available for ${system}");

  src = fetchurl {
    url = "https://github.com/mensfeld/code-on-incus/releases/download/v${version}/${asset}";
    hash =
      {
        x86_64-linux = "sha256-SSmGxYp3gUJclX4fdTB50ALHnN00l1ps9PMbzo0ytxY=";
        aarch64-linux = "sha256-+wCe/IgBmYJwKqzOug7QYtw3r9cNbUGiOIlIdNMNvdQ=";
      }.${system};
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version src;

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/coi"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Incus sandbox runtime for coding agents";
    homepage = "https://github.com/mensfeld/code-on-incus";
    changelog = "https://github.com/mensfeld/code-on-incus/releases/tag/v${version}";
    license = licenses.mit;
    mainProgram = "coi";
    maintainers = [ ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
