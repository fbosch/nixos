{ fetchFromGitHub
, lib
, stdenvNoCC
, uv
,
}:

stdenvNoCC.mkDerivation rec {
  pname = "headroom";
  version = "0.30.0";

  src = fetchFromGitHub {
    owner = "headroomlabs-ai";
    repo = "headroom";
    rev = "v${version}";
    hash = "sha256-BxZq6UzmLae7eNrE7iUuunM3hRM4E41i4j6LsKFyFdk=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    cat > "$out/bin/headroom" <<EOF
    #!${stdenvNoCC.shell}
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
