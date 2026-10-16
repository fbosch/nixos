{
  lib,
  autoPatchelfHook,
  fetchurl,
  makeWrapper,
  nodejs_24,
  stdenv,
  stdenvNoCC,
  ...
}:

let
  nativeBinaryPackages = {
    "aarch64-darwin" = {
      package = "exe.darwin-arm64";
      hash = "sha512-tnrdUB8ecJoehuKKqi1YHCBVl61xtJ9XVGcx5EviC6fWO4DeGI8GtXrjvJxDBM3nuVjJeWistgsUp/N142x4sw==";
    };
    "x86_64-linux" = {
      package = "exe.linux-x64";
      hash = "sha512-F6K8e/jWxiuEYJaQtRRUG9ynBSTEHa+t7Lf86MKuOO5UA7WVVMbi+oB8nY6iKW++ncWS2yG6T9faXZGxqNsfoQ==";
    };
  };
  nativeBinaryPackage =
    nativeBinaryPackages.${stdenvNoCC.hostPlatform.system}
      or (throw "pnpm has no pinned native binary for ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation rec {
  pname = "pnpm";
  version = "12.14.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/pnpm/-/pnpm-${version}.tgz";
    hash = "sha256-6iBuNUdL+HvpVkqFynDtHI69xF2lWq+wo78J0bppsXk=";
  };

  nativeSrc = fetchurl {
    url = "https://registry.npmjs.org/@pnpm/${nativeBinaryPackage.package}/-/${nativeBinaryPackage.package}-${version}.tgz";
    hash = nativeBinaryPackage.hash;
  };

  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    (lib.getLib stdenv.cc.cc)
  ];

  doInstallCheck = true;

  installCheckPhase = ''
    $out/bin/pnpm --version >/dev/null
    $out/bin/pnpx --help >/dev/null
    $out/bin/pn --version >/dev/null
    $out/bin/pnx --help >/dev/null
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/node_modules/pnpm" "$out/bin"
    cp -R . "$out/lib/node_modules/pnpm"

    native_binary_dir="$out/lib/node_modules/pnpm/node_modules/@pnpm/${nativeBinaryPackage.package}"
    mkdir -p "$native_binary_dir"
    tar -xzf "${nativeSrc}" --strip-components=1 -C "$native_binary_dir"

    makeWrapper ${nodejs_24}/bin/node "$out/bin/pnpm" \
      --add-flags "$out/lib/node_modules/pnpm/bin/pnpm.mjs"
    makeWrapper ${nodejs_24}/bin/node "$out/bin/pnpx" \
      --add-flags "$out/lib/node_modules/pnpm/bin/pnpx.mjs"
    ln -s pnpm "$out/bin/pn"
    ln -s pnpx "$out/bin/pnx"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Fast, disk space efficient package manager for JavaScript";
    homepage = "https://pnpm.io/";
    changelog = "https://github.com/pnpm/pnpm/releases/tag/v${version}";
    license = licenses.mit;
    mainProgram = "pnpm";
    maintainers = [ ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    platforms = builtins.attrNames nativeBinaryPackages;
  };
}
