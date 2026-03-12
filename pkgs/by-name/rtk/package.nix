{ fetchFromGitHub
, lib
, rustPlatform
,
}:

rustPlatform.buildRustPackage rec {
  pname = "rtk";
  version = "0.29.0";

  src = fetchFromGitHub {
    owner = "rtk-ai";
    repo = "rtk";
    rev = "v${version}";
    hash = "sha256-QGHCa8rO4YBFXdrz78FhWKFxY7DmRxCXM8iYQv4yTYE=";
  };

  cargoHash = "sha256-gNJjtQah7NFSgFVYJftK19dECzDvLCi2E33na2PtKmc=";

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
