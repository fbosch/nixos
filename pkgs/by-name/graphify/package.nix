{ lib
, stdenvNoCC
, uv
,
}:

stdenvNoCC.mkDerivation rec {
  pname = "graphify";
  version = "0.9.31";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    cat > "$out/bin/graphify" <<EOF
    #!${stdenvNoCC.shell}
    exec ${uv}/bin/uvx --python 3.10 --from 'graphifyy==${version}' graphify "\$@"
    EOF
    chmod +x "$out/bin/graphify"
    runHook postInstall
  '';

  meta = with lib; {
    description = "CLI for turning codebases into queryable knowledge graphs";
    homepage = "https://github.com/Graphify-Labs/graphify";
    license = licenses.asl20;
    mainProgram = "graphify";
    maintainers = [ ];
    platforms = platforms.unix;
  };
}
