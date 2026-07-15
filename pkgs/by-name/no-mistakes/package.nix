{ lib
, buildGoModule
, fetchFromGitHub
,
}:

buildGoModule rec {
  pname = "no-mistakes";
  version = "1.37.0";

  src = fetchFromGitHub {
    owner = "kunchenguid";
    repo = "no-mistakes";
    rev = "v${version}";
    hash = "sha256-gNxnW73qGIdO4j8P6gkpvW1WOtUO2gpFgNf9Dhhx6BA=";
  };

  vendorHash = "sha256-NZOYxNYvt4192uqKBdKRxdgrKFvWx3585psdCnRdPSM=";

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
