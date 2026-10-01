{ lib
, fetchFromGitHub
, python3Packages
,
}:

python3Packages.buildPythonApplication rec {
  pname = "caliper";
  version = "0.16.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "edonadei";
    repo = "caliper";
    tag = "v${version}";
    hash = "sha256-6nRZsvwxj0Bgvvx11VNcTl0FF9fWszOD5NnUevScZ3Y=";
  };

  build-system = [ python3Packages.hatchling ];

  dependencies = [
    python3Packages.click
    python3Packages.psutil
    python3Packages.pydantic
    python3Packages.pyyaml
    python3Packages.rich
    python3Packages.tomli-w
    python3Packages.typer
  ];

  pythonImportsCheck = [ "caliper" ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/caliper --help >/dev/null
    runHook postInstallCheck
  '';

  meta = {
    description = "Lightweight evaluation harness for agent skills";
    homepage = "https://github.com/edonadei/caliper";
    license = lib.licenses.mit;
    mainProgram = "caliper";
    maintainers = [ ];
    platforms = lib.platforms.unix;
  };
}
