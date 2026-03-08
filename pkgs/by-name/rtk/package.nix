{ fetchFromGitHub
, lib
, rustPlatform
,
}:

rustPlatform.buildRustPackage rec {
  pname = "rtk";
  version = "0.27.2";

  src = fetchFromGitHub {
    owner = "rtk-ai";
    repo = "rtk";
    rev = "v${version}";
    hash = "sha256-95vOlmFKgAuGpGQfLTsNdVBVbOQJRuFLzYbrCVwj/iY=";
  };

  cargoHash = "sha256-ygkLwspnSh4sk0jcWFCzJGVtzZ+bTelMqfMT9Jm1lMI=";

  doCheck = false;

  meta = with lib; {
    description = "CLI proxy that reduces LLM token consumption by 60-90%";
    homepage = "https://www.rtk-ai.app";
    changelog = "https://github.com/rtk-ai/rtk/releases/tag/v${version}";
    license = licenses.mit;
    mainProgram = "rtk";
    maintainers = [ ];
    platforms = platforms.unix;
    sourceProvenance = with sourceTypes; [ fromSource ];
  };
}
