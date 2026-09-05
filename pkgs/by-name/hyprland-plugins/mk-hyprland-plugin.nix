{ inputs, stdenv }:

{ pname
, version
, src
, description
, doCheck ? false
, extraFiles ? [ ]
,
}:

let
  pkgs = import inputs.hyprland.inputs.nixpkgs {
    inherit (stdenv.hostPlatform) system;
  };
  inherit (pkgs) lib;
  hyprland = inputs.hyprland.packages.${stdenv.hostPlatform.system}.hyprland;
  pluginRoot = ./.;
  # Darwin must be able to inspect meta.platforms without evaluating Hyprland's Linux-only linker.
  pluginStdenv = if stdenv.hostPlatform.isLinux then hyprland.stdenv else stdenv;
in
pluginStdenv.mkDerivation {
  inherit pname version doCheck;

  src = lib.fileset.toSource {
    root = pluginRoot;
    fileset = lib.fileset.unions (
      [ (lib.fileset.difference src (lib.fileset.maybeMissing (src + "/build"))) ] ++ extraFiles
    );
  };
  sourceRoot = "source/${pname}";

  nativeBuildInputs = [
    pkgs.cmake
    pkgs.pkg-config
  ];
  buildInputs = hyprland.buildInputs ++ [ hyprland ];
  cmakeFlags = lib.optionals doCheck [ "-DBUILD_TESTING=ON" ];

  checkPhase = ''
    runHook preCheck
    ctest --output-on-failure --no-tests=error
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 lib${pname}.so $out/lib/lib${pname}.so
    runHook postInstall
  '';

  meta = {
    inherit description;
    license = lib.licenses.mit;
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
  };
}
