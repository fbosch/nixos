{ fetchurl
, lib
, nix-update-script
, stdenvNoCC
,
}:

let
  version = "2.2.0";
  sources = {
    aarch64-darwin = {
      name = "darwin-arm64";
      hash = "sha256-bxXppEIErs95MQq0vMmda8g7qUQ577LrcrVGif5pxBI=";
    };
    x86_64-darwin = {
      name = "darwin-amd64";
      hash = "sha256-iqVWCOFq83JspKteqTq1NJA+g7SBe4OO07rOQ9YTKo4=";
    };
    aarch64-linux = {
      name = "linux-arm64";
      hash = "sha256-l8xiBBzOvCncRWMf93TOuL4gpY4SKqRSjb9E9IpnlR4=";
    };
    x86_64-linux = {
      name = "linux-amd64";
      hash = "sha256-HG0t2r6K7TVSXZpsjxlHgEIRi1fXBjX6eTNXqlkpg+M=";
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
