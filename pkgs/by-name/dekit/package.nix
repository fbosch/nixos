{ fetchFromGitHub
, curl
, lib
, rustPlatform
,
}:

rustPlatform.buildRustPackage rec {
  pname = "dekit";
  version = "0.10.2";

  src = fetchFromGitHub {
    owner = "pvolok";
    repo = "dekit";
    rev = "v${version}";
    hash = "sha256-4EcWcYnL9Ua9pQ0K8hIRLVOcHfK3V9T9LS0LDVpH0dw=";
  };

  patches = [
    ./register-idle-tasks.patch
    ./inherit-terminal-theme.patch
  ];
  cargoHash = "sha256-0fLXXJouIOy/8fcKhneEYIuGj3EzTL+owSVEEsxGNRg=";

  nativeBuildInputs = [ curl ];

  # v0.10.2's API-doc test expects std.tui, which upstream registers only in debug builds.
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
