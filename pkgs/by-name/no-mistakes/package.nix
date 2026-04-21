{ lib
, buildGoModule
, fetchFromGitHub
,
}:

buildGoModule rec {
  pname = "no-mistakes";
  version = "1.8.0";

  src = fetchFromGitHub {
    owner = "kunchenguid";
    repo = "no-mistakes";
    rev = "v${version}";
    hash = "sha256-fmUYnGjatSCqqK4sWHP56SnoqhI7lxTFX2kJ/AYZiqY=";
  };

  vendorHash = "sha256-jX801hUq4x7xchpXQ5MRu32p4JG1Ii/Z4vqFTMyNjIg=";

  subPackages = [ "cmd/no-mistakes" ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/kunchenguid/no-mistakes/internal/buildinfo.Version=v${version}"
  ];

  env = {
    CGO_ENABLED = 0;
  };

  doCheck = false;

  meta = with lib; {
    description = "AI-powered git push gate that validates and auto-opens clean PRs";
    homepage = "https://github.com/kunchenguid/no-mistakes";
    changelog = "https://github.com/kunchenguid/no-mistakes/releases/tag/v${version}";
    license = licenses.mit;
    mainProgram = "no-mistakes";
    maintainers = [ ];
    platforms = platforms.unix;
    sourceProvenance = with sourceTypes; [ fromSource ];
  };
}
