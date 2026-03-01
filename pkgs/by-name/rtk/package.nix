{ lib
, stdenv
, fetchurl
,
}:

stdenv.mkDerivation rec {
  pname = "rtk";
  version = "0.23.0";

  src = fetchurl {
    url = "https://github.com/rtk-ai/rtk/releases/download/v${version}/rtk-x86_64-unknown-linux-musl.tar.gz";
    hash = "sha256-0ZditeSuyPE9XaJWMfA7xqxnLV/sjWff9wToySGC4sk=";
  };

  dontBuild = true;
  dontConfigure = true;

  unpackPhase = ''
    tar xf $src
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 rtk $out/bin/rtk
    runHook postInstall
  '';

  meta = with lib; {
    description = "CLI proxy that reduces LLM token consumption by 60-90%";
    homepage = "https://github.com/rtk-ai/rtk";
    changelog = "https://github.com/rtk-ai/rtk/releases/tag/v${version}";
    license = licenses.mit;
    mainProgram = "rtk";
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
