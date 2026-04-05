{ fetchFromGitHub
, lib
, rustPlatform
,
}:

rustPlatform.buildRustPackage rec {
  pname = "rtk";
  version = "0.34.3";

  src = fetchFromGitHub {
    owner = "rtk-ai";
    repo = "rtk";
    rev = "v${version}";
    hash = "sha256-SQJhPit7efAjBezCNHtn5iZEEly6eApxsO9jGHLrKlg=";
  };

  cargoHash = "sha256-WpSwEx/pkGTIlDv1cTFtTcTC3YgddMYVbOLlqKYeDK0=";

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
