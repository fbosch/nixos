{ fetchFromGitHub
, lib
, stdenv
, uv
,
}:

stdenv.mkDerivation rec {
  pname = "headroom";
  version = "0.31.0";

  src = fetchFromGitHub {
    owner = "headroomlabs-ai";
    repo = "headroom";
    rev = "v${version}";
    hash = "sha256-A04h+wTlGBZVXW6ujb8bYdtM2Y16SbntwnNy48qaA7g=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    cat > "$out/bin/headroom" <<EOF
    #!${stdenv.shell}
    export LD_LIBRARY_PATH="${
      lib.makeLibraryPath [ stdenv.cc.cc.lib ]
    }\''${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
    exec ${uv}/bin/uvx --from 'headroom-ai[proxy]==${version}' headroom "\$@"
    EOF
    chmod +x "$out/bin/headroom"
    runHook postInstall
  '';

  meta = with lib; {
    description = "CLI and MCP server for compressing AI agent context";
    homepage = "https://github.com/headroomlabs-ai/headroom";
    changelog = "https://github.com/headroomlabs-ai/headroom/releases/tag/v${version}";
    license = licenses.asl20;
    mainProgram = "headroom";
    maintainers = [ ];
    platforms = platforms.unix;
  };
}
