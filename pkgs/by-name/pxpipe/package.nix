{ fetchFromGitHub
, fetchPnpmDeps
, lib
, makeWrapper
, nodejs
, pnpm_10
, pnpmConfigHook
, stdenvNoCC
,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pxpipe";
  version = "0.7.1";

  src = fetchFromGitHub {
    owner = "teamchong";
    repo = "pxpipe";
    rev = "v${finalAttrs.version}";
    hash = "sha256-T/ygIrnpnCg5TuCpHAlJGzO2soA6WNRje9pUDWTq4bQ=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname;
    inherit (finalAttrs) version src;
    pnpm = pnpm_10;
    hash = "sha256-xMTK9VGDdijk/EsVdY5XrpwXSOlLdd0Njc00GjzJ8rc=";
    fetcherVersion = 4;
  };

  nativeBuildInputs = [
    makeWrapper
    nodejs
    pnpm_10
    pnpmConfigHook
  ];

  buildPhase = ''
    runHook preBuild
    pnpm run build
    pnpm prune --prod
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/pxpipe" "$out/bin"
    cp -r bin dist node_modules package.json "$out/lib/pxpipe"
    makeWrapper ${nodejs}/bin/node "$out/bin/pxpipe" \
      --add-flags "$out/lib/pxpipe/bin/cli.js"
    runHook postInstall
  '';

  meta = {
    description = "Local proxy that renders bulky AI context as images";
    homepage = "https://github.com/teamchong/pxpipe";
    changelog = "https://github.com/teamchong/pxpipe/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "pxpipe";
    maintainers = [ ];
    platforms = lib.platforms.unix;
  };
})
