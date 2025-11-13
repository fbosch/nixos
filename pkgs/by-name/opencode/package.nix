{ lib
, stdenvNoCC
, bun
, fetchFromGitHub
, fzf
, makeBinaryWrapper
, models-dev
, nix-update-script
, ripgrep
, testers
, writableTmpDirAsHomeHook
, # Allow overriding source for easier updates
  opencode-src ? null
, opencode-version ? "1.0.63-dev"
,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "opencode";
  version = opencode-version;
  src = if opencode-src != null then opencode-src else
  fetchFromGitHub {
    owner = "sst";
    repo = "opencode";
    rev = "a673e3650d8f1d2fdebc4c6490280f43b4459e68";
    hash = "sha256-EeCwCY8vYpFFc9tApSlptMQ3XtXYSQj8hQ8LHOZCboI=";
  };

  node_modules = stdenvNoCC.mkDerivation {
    pname = "opencode-node_modules";
    inherit (finalAttrs) version src;

    impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [
      "GIT_PROXY_COMMAND"
      "SOCKS_SERVER"
    ];

    nativeBuildInputs = [
      bun
      writableTmpDirAsHomeHook
    ];

    dontConfigure = true;

    buildPhase = ''
      runHook preBuild

      export BUN_INSTALL_CACHE_DIR=$(mktemp -d)

      bun install \
        --filter=./packages/opencode \
        --force \
        --frozen-lockfile \
        --ignore-scripts \
        --linker=hoisted \
        --no-progress \
        --production

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/node_modules
      cp -R ./node_modules $out

      runHook postInstall
    '';

    dontFixup = true;

    outputHash = (lib.importJSON ./hashes.json).node_modules.${stdenvNoCC.hostPlatform.system};
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
  };

  nativeBuildInputs = [
    bun
    makeBinaryWrapper
    models-dev
  ];

  patches = [
    ./local-models-dev.patch
    ./skip-bun-install.patch
  ];

  postPatch = ''
    substituteInPlace packages/script/src/index.ts \
      --replace-fail "if (process.versions.bun !== expectedBunVersion)" "if (false)"
  '';

  configurePhase = ''
    runHook preConfigure

    cd packages/opencode
    cp -R ${finalAttrs.node_modules}/. .

    chmod -R u+w ./node_modules
    rm ./node_modules/@opencode-ai/script
    ln -s $(pwd)/../../packages/script ./node_modules/@opencode-ai/script
    rm -f ./node_modules/@opencode-ai/sdk
    ln -s $(pwd)/../../packages/sdk/js ./node_modules/@opencode-ai/sdk
    rm -f ./node_modules/@opencode-ai/plugin
    ln -s $(pwd)/../../packages/plugin ./node_modules/@opencode-ai/plugin

    runHook postConfigure
  '';

  env = {
    MODELS_DEV_API_JSON = "${models-dev}/dist/_api.json";
    OPENCODE_VERSION = finalAttrs.version;
    OPENCODE_CHANNEL = "dev";
  };

  buildPhase = ''
    runHook preBuild

    bun run ./script/build.ts --single

    runHook postBuild
  '';

  dontStrip = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 dist/opencode-*/bin/opencode $out/bin/opencode

    runHook postInstall
  '';

  postInstall = ''
    wrapProgram $out/bin/opencode \
      --prefix PATH : ${
        lib.makeBinPath [
          fzf
          ripgrep
        ]
      }
  '';

  passthru = {
    tests.version = testers.testVersion {
      package = finalAttrs.finalPackage;
      command = "HOME=$(mktemp -d) opencode --version";
      inherit (finalAttrs) version;
    };
    updateScript = nix-update-script {
      extraArgs = [
        "--subpackage"
        "node_modules"
      ];
    };
  };

  meta = {
    description = "AI coding agent built for the terminal";
    longDescription = ''
      OpenCode is a terminal-based agent that can build anything.
      It combines a TypeScript/JavaScript core with a Go-based TUI
      to provide an interactive AI coding experience.
    '';
    homepage = "https://github.com/sst/opencode";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "opencode";
  };
})
