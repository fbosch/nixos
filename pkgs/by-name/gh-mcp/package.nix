{ fetchurl
, lib
, nix-update-script
, stdenvNoCC
,
}:

let
  version = "3.7.0";
  sources = {
    aarch64-darwin = {
      name = "darwin-arm64";
      hash = "sha256-C3S5/EqoE1K/IMwpEru5XUnKOxHTcgkkJFPsRKBBY6w=";
    };
    x86_64-darwin = {
      name = "darwin-amd64";
      hash = "sha256-q9IcM5MD1xEchP1EMcW3GfNeQ/1W/z0OiXgbEoKMNlQ=";
    };
    aarch64-linux = {
      name = "linux-arm64";
      hash = "sha256-E+PNfF3uzwCGmR9yRmZ01OW3FCkiL06xCRRZi4qNQyY=";
    };
    x86_64-linux = {
      name = "linux-amd64";
      hash = "sha256-zh3t1ZJUiXPK3EMOn/2ta8Yfj1FceFSLzD7pc+J8R8E=";
    };
  };
  source =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "gh-mcp is not packaged for ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "gh-mcp";
  inherit version;

  src = fetchurl {
    url = "https://github.com/shuymn/gh-mcp/releases/download/v${version}/${source.name}";
    inherit (source) hash;
  };

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/gh-mcp"
    install -Dm755 "$src" "$out/share/gh/extensions/gh-mcp/gh-mcp"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x "$out/bin/gh-mcp"
    test -x "$out/share/gh/extensions/gh-mcp/gh-mcp"
    runHook postInstallCheck
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--use-github-releases"
    ];
  };

  meta = with lib; {
    description = "GitHub CLI extension providing an MCP server";
    homepage = "https://github.com/shuymn/gh-mcp";
    changelog = "https://github.com/shuymn/gh-mcp/releases/tag/v${version}";
    license = licenses.mit;
    mainProgram = "gh-mcp";
    maintainers = [ ];
    platforms = builtins.attrNames sources;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
