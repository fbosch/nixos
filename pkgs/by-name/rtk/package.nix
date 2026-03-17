{ fetchFromGitHub
, lib
, rustPlatform
,
}:

rustPlatform.buildRustPackage rec {
  pname = "rtk";
  version = "0.30.0";

  src = fetchFromGitHub {
    owner = "rtk-ai";
    repo = "rtk";
    rev = "v${version}";
    hash = "sha256-aB9SWF9jYHeH3Apz5v4mQptLa6tS9cIfyfo6rHqsD8w=";
  };

  cargoHash = "sha256-0dpZRBPubzd2GuK02/jbNBWOR/TpFM5lVMucEii/JxM=";

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
