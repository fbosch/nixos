{ lib
, stdenvNoCC
, fetchurl
, makeWrapper
, nodejs_24
, ...
}:

stdenvNoCC.mkDerivation rec {
  pname = "pnpm";
  version = "11.5.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/pnpm/-/pnpm-${version}.tgz";
    hash = "sha256-3npcG+2DAYBRg6h5l/4XIM1crvtXvoOFNaS/xKFZaVk=";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/node_modules/pnpm" "$out/bin"
    cp -R . "$out/lib/node_modules/pnpm"

    makeWrapper ${nodejs_24}/bin/node "$out/bin/pnpm" \
      --add-flags "$out/lib/node_modules/pnpm/bin/pnpm.mjs"
    makeWrapper ${nodejs_24}/bin/node "$out/bin/pnpx" \
      --add-flags "$out/lib/node_modules/pnpm/bin/pnpx.mjs"
    ln -s pnpm "$out/bin/pn"
    ln -s pnpx "$out/bin/pnx"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Fast, disk space efficient package manager for JavaScript";
    homepage = "https://pnpm.io/";
    changelog = "https://github.com/pnpm/pnpm/releases/tag/v${version}";
    license = licenses.mit;
    mainProgram = "pnpm";
    maintainers = [ ];
    platforms = platforms.unix;
  };
}
