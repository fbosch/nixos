{ lib
, buildGoModule
, fetchFromGitHub
, nix-update-script
,
}:

buildGoModule (finalAttrs: {
  pname = "surge";
  version = "0.12.3";

  src = fetchFromGitHub {
    owner = "SurgeDM";
    repo = "Surge";
    tag = "v${finalAttrs.version}";
    hash = "sha256-srR4nK5DzK+EMgWYx0kl43sqXCmSwmFMM0rIyG5XjAY=";
  };

  vendorHash = "sha256-q1rYIzBFIZrQ3fuvBMohBdlR8+bLHl+w7kYFjHkWMSI=";

  # Release sources include a stale vendor tree; regenerate it from go.mod/go.sum.
  postPatch = ''
    rm -rf vendor
  '';

  subPackages = [ "." ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/SurgeDM/Surge/cmd.Version=${finalAttrs.version}"
  ];

  # Upstream tests write configuration files under HOME.
  preCheck = ''
    export HOME="$TMPDIR"
  '';

  postInstall = ''
    ln -s Surge "$out/bin/surge"
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$("$out/bin/Surge" --version)" = "Surge v${finalAttrs.version}"
    test "$("$out/bin/surge" --version)" = "Surge v${finalAttrs.version}"
    runHook postInstallCheck
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };

  meta = {
    description = "Blazing fast TUI download manager built in Go";
    homepage = "https://github.com/SurgeDM/Surge";
    changelog = "https://github.com/SurgeDM/Surge/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "surge";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
