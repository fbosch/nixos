{
  lib,
  fetchFromGitHub,
  fetchzip,
  glslang,
  meson,
  ninja,
  pkgsCross,
  stdenvNoCC,
  winePackages,
}:

let
  geVersion = "GE-Proton11-7";
  geToolName = "proton-wow";
  vkd3dCommit = "af89350cc2eacd9da2293fbae96bd9ab4987c9bb";

  vkd3dSource = fetchFromGitHub {
    owner = "HansKristian-Work";
    repo = "vkd3d-proton";
    rev = vkd3dCommit;
    fetchSubmodules = true;
    hash = "sha256-K6nrw1rbEbqYNwpj1vMkibfHK9gVGi81W0kUYJb6G9Q=";
  };

  targetPthreads =
    package:
    package.overrideAttrs (_: {
      # This package contributes Windows libraries to a Linux cross-build.
      meta.platforms = [
        "x86_64-linux"
        "x86_64-windows"
        "i686-windows"
      ];
    });

  buildVkd3d =
    {
      arch,
      crossCompiler,
      crossFile,
      crossPthreads,
    }:
    let
      widlTarget = if arch == "64" then "x86_64-w64-mingw32-widl" else "i686-w64-mingw32-widl";
    in
    stdenvNoCC.mkDerivation {
      pname = "${geToolName}-vkd3d-proton-${arch}";
      version = "3.1.0-${vkd3dCommit}";
      src = vkd3dSource;

      patches = [
        ./ge-vkd3d-present-wait.patch
        ./vkd3d-options5-logging.patch
      ];

      nativeBuildInputs = [
        crossCompiler
        crossPthreads
        glslang
        meson
        ninja
        winePackages.minimal
      ];

      strictDeps = true;
      NIX_CFLAGS_COMPILE = "-I${crossPthreads}/include";
      NIX_LDFLAGS = "-L${crossPthreads}/lib";

      postPatch = ''
        substituteInPlace ${crossFile} \
          --replace-fail "${widlTarget}" "${winePackages.minimal}/bin/widl"
        substituteInPlace meson.build \
          --replace-fail "fallback : '12345678'" "fallback : 'af89350cc2eacd9'" \
          --replace-fail "fallback : '301000'" "fallback : 'vkd3d-1.1-5604-gaf89350cc'"
      '';

      configurePhase = ''
        runHook preConfigure
        meson setup build.${arch} \
          --cross-file ${crossFile} \
          --buildtype release \
          --prefix "$out" \
          --bindir x${arch} \
          --libdir x${arch} \
          -Denable_trace=false
        runHook postConfigure
      '';

      buildPhase = ''
        runHook preBuild
        ninja -C build.${arch}
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        ninja -C build.${arch} install
        test -f "$out/x${arch}/d3d12.dll"
        test -f "$out/x${arch}/d3d12core.dll"
        runHook postInstall
      '';

      dontFixup = true;
    };

  vkd3dProton64 = buildVkd3d {
    arch = "64";
    crossCompiler = pkgsCross.mingwW64.stdenv.cc;
    crossFile = "build-win64.txt";
    crossPthreads = targetPthreads pkgsCross.mingwW64.windows.pthreads;
  };

  vkd3dProton32 = buildVkd3d {
    arch = "86";
    crossCompiler = pkgsCross.mingw32.stdenv.cc;
    crossFile = "build-win32.txt";
    crossPthreads = targetPthreads pkgsCross.mingw32.windows.pthreads;
  };

  geSource = fetchzip {
    url = "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${geVersion}/${geVersion}-x86_64.tar.gz";
    hash = "sha256-ftW0vE45v2JsbaYqo/So0ZFfvdtakHX0XEXEE4TdxLk=";
  };
in
stdenvNoCC.mkDerivation {
  pname = geToolName;
  version = geVersion;
  src = geSource;

  outputs = [
    "out"
    "steamcompattool"
  ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    echo "${geToolName} is a Steam compatibility tool. Use the Steam or Faugus runner discovery paths." > "$out"
    mkdir "$steamcompattool"
    cp -a "$src"/. "$steamcompattool"/

    substituteInPlace "$steamcompattool/compatibilitytool.vdf" \
      --replace-fail "GE-Proton11-7-x86_64" "${geToolName}"

    chmod -R u+w "$steamcompattool/files/lib/wine/vkd3d-proton"

    cp "${vkd3dProton64}/x64/d3d12.dll" \
      "$steamcompattool/files/lib/wine/vkd3d-proton/x86_64-windows/d3d12.dll"
    cp "${vkd3dProton64}/x64/d3d12core.dll" \
      "$steamcompattool/files/lib/wine/vkd3d-proton/x86_64-windows/d3d12core.dll"
    cp "${vkd3dProton32}/x86/d3d12.dll" \
      "$steamcompattool/files/lib/wine/vkd3d-proton/i386-windows/d3d12.dll"
    cp "${vkd3dProton32}/x86/d3d12core.dll" \
      "$steamcompattool/files/lib/wine/vkd3d-proton/i386-windows/d3d12core.dll"

    runHook postInstall
  '';

  passthru = {
    inherit geVersion geToolName vkd3dCommit;
    vkd3dProton = {
      inherit vkd3dProton32 vkd3dProton64;
    };
  };

  meta = {
    description = "GE-Proton11-7 compatibility tool with a pinned VKD3D-Proton build and bounded OPTIONS5 diagnostics";
    homepage = "https://github.com/GloriousEggroll/proton-ge-custom";
    license = [
      lib.licenses.bsd3
      lib.licenses.lgpl21Plus
    ];
    mainProgram = "proton";
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [
      binaryNativeCode
      fromSource
    ];
  };
}
