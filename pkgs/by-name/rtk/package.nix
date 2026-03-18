{ fetchFromGitHub
, lib
, rustPlatform
,
}:

rustPlatform.buildRustPackage rec {
  pname = "rtk";
  version = "0.30.1";

  src = fetchFromGitHub {
    owner = "rtk-ai";
    repo = "rtk";
    rev = "v${version}";
    hash = "sha256-SIUtQ2y4O5F5ib8N9GKmsrd07CCtYco+Q3DInEd0uSw=";
  };

  cargoHash = "sha256-zJohVBlj6nFpfg6+E6Isnhxr9Tmhw5xW5tRF0HKmVXY=";

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
