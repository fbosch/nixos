{ lib
, stdenv
, stdenvNoCC
, autoPatchelfHook
, makeWrapper
, fetchurl
, curl
, libxml2
, sqlite
,
}:

let
  pname = "codexbar";
  version = "0.18.0-beta.2";

  inherit (stdenvNoCC.hostPlatform) system;
  arch =
    {
      x86_64-linux = "x86_64";
      aarch64-linux = "aarch64";
    }.${system} or (throw "${pname} is not available for ${system}");

  src = fetchurl {
    url = "https://github.com/steipete/CodexBar/releases/download/v${version}/CodexBarCLI-v${version}-linux-${arch}.tar.gz";
    hash =
      {
        x86_64-linux = "sha256-oaAT1LaYivJZt6n5lukkg8oQoeUEbNfjRiV5DvHVkCk=";
        aarch64-linux = "sha256-/TsvvMod3IMaZhEirQmu/oOC94f0yAsLCdnkzqob3b4=";
      }.${system};
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version src;

  dontBuild = true;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  autoPatchelfIgnoreMissingDeps = [ "libxml2.so.2" ];
  autoPatchelfLibs = [ libxml2.out ];
  buildInputs = [
    curl
    libxml2.out
    sqlite
    stdenv.cc.cc.lib
  ];

  unpackPhase = ''
    runHook preUnpack
    tar -xf $src
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 CodexBarCLI $out/bin/CodexBarCLI
    install -Dm755 codexbar $out/bin/codexbar

    mkdir -p $out/lib
    ln -s ${libxml2.out}/lib/libxml2.so.16 $out/lib/libxml2.so.2

    wrapProgram $out/bin/codexbar \
      --prefix LD_LIBRARY_PATH : "$out/lib"

    wrapProgram $out/bin/CodexBarCLI \
      --prefix LD_LIBRARY_PATH : "$out/lib"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Menu bar app and CLI for tracking AI usage";
    homepage = "https://github.com/steipete/CodexBar";
    license = licenses.mit;
    mainProgram = "codexbar";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = [ ];
  };
}
