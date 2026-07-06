{ fetchFromGitHub
, lib
, stdenvNoCC
, uv
,
}:

stdenvNoCC.mkDerivation rec {
  pname = "headroom";
  version = "0.27.0";

  src = fetchFromGitHub {
    owner = "headroomlabs-ai";
    repo = "headroom";
    rev = "v${version}";
    hash = "sha256-059AC105XH6BOnHvQjC3EueUL3Z6t1fD29fHqHkkmX0=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    cat > "$out/bin/headroom" <<EOF
    #!${stdenvNoCC.shell}
    exec ${uv}/bin/uvx --from 'headroom-ai[mcp]==${version}' headroom "\$@"
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
