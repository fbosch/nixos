{ lib
, buildGoModule
, fetchFromGitHub
,
}:

buildGoModule rec {
  pname = "no-mistakes";
  version = "1.31.2";

  src = fetchFromGitHub {
    owner = "kunchenguid";
    repo = "no-mistakes";
    rev = "v${version}";
    hash = "sha256-fUzPGmzxJWheRaq+dDKOJmupL7V0XDW8ZSEDpJs5/b0=";
  };

  vendorHash = "sha256-2pjiHVUwdQpXG9HTLW6wMZD+JpvFEcPMgBsVc6sck6w=";

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
