{
  fetchFromGitHub,
  curl,
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage rec {
  pname = "dekit";
  version = "0.10.0";

  src = fetchFromGitHub {
    owner = "pvolok";
    repo = "dekit";
    rev = "v${version}";
    hash = "sha256-Kj+iWiRyRavCHgpZLPUPWqeItlD079OTO0lkaS3qpsc=";
  };

  cargoHash = "sha256-g7RJa3wOv4tr7IW3SWHie78t3qTqHV3HMHobgQW2jS8=";

  nativeBuildInputs = [ curl ];

  # v0.10.0's API-doc test expects std.tui, which upstream registers only in debug builds.
  checkType = "debug";

  # shortcut: This upstream integration test passes outside the build sandbox but
  # times out inside it. Remove the skip when the test is sandbox-safe.
  checkFlags = [ "--skip=commands_that_cannot_run_are_reported" ];
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    test "$("$out/bin/dekit" --version)" = "dekit ${version}"
    "$out/bin/dekit" --json --help >/dev/null

    runHook postInstallCheck
  '';

  meta = {
    description = "Process manager for dev and prod";
    homepage = "https://dekit.run";
    license = lib.licenses.mit;
    mainProgram = "dekit";
    maintainers = [ ];
    platforms = lib.platforms.unix;
  };
}
