{ fetchurl
, lib
, nix-update-script
, stdenvNoCC
,
}:

let
  sources = {
    x86_64-linux = {
      url = "https://github.com/dmtrKovalenko/fff.nvim/releases/download/v0.9.6/fff-mcp-x86_64-unknown-linux-musl";
      hash = "sha256-ECzq8XPvd2vsszIiFun2tcrvmXxADF0V8RLOTeQKH1o=";
    };
  };

  source =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "fff-mcp is not packaged for ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation rec {
  pname = "fff-mcp";
  version = "0.9.6";

  src = fetchurl source;

  dontUnpack = true;

  doInstallCheck = true;

  installCheckPhase = ''
    $out/bin/fff-mcp --help >/dev/null
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
      "--version-regex=^v([0-9]+\\.[0-9]+\\.[0-9]+)$"
    ];
  };

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/fff-mcp
    runHook postInstall
  '';

  meta = with lib; {
    description = "Fast file search toolkit for AI agents (MCP server)";
    homepage = "https://github.com/dmtrKovalenko/fff";
    changelog = "https://github.com/dmtrKovalenko/fff/releases/tag/v${version}";
    license = licenses.mit;
    mainProgram = "fff-mcp";
    maintainers = [ ];
    platforms = builtins.attrNames sources;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
