{ lib
, fetchurl
, appimageTools
, asar
, nss_latest
, writeShellScript
,
}:

let
  pname = "openpets";
  version = "2.0.6";

  src = fetchurl {
    url = "https://github.com/alvinunreal/openpets/releases/download/v${version}/OpenPets-${version}-linux-x86_64.AppImage";
    hash = "sha256-ai83j9N1KdWt6K+vhtU3FQTi7mfi0mSLIiAlcJevHNc=";
  };

  appimageContents = appimageTools.extractType2 { inherit pname version src; };

  sharpLinuxX64 = fetchurl {
    url = "https://registry.npmjs.org/@img/sharp-linux-x64/-/sharp-linux-x64-0.34.5.tgz";
    hash = "sha512-MEzd8HPKxVxVenwAa+JRPwEC7QFjoPWuS5NZnBt6B3pu7EG2Ge0id1oLHZpPJdn3OQK+BQDiw9zStiHBTJQQQQ==";
  };

  sharpLibvipsLinuxX64 = fetchurl {
    url = "https://registry.npmjs.org/@img/sharp-libvips-linux-x64/-/sharp-libvips-linux-x64-1.2.4.tgz";
    hash = "sha512-tJxiiLsmHc9Ax1bz3oaOYBURTXGIRDODBqhveVHonrHJ9/+k89qbLl0bcJns+e4t4rvaNBxaEZsFtSfAdquPrw==";
  };

  appimageInit = writeShellScript "openpets-appimage-init" ''
    source /etc/profile
    exec appimage-exec.sh -w @appDir@ -- "$@"
  '';
in
appimageTools.wrapType2 {
  inherit pname version src;

  nativeBuildInputs = [
    asar
  ];

  extraPkgs =
    pkgs: with pkgs; [
      nss_latest
    ];

  extraInstallCommands = ''
    patchedAppDir="$out/share/${pname}/appimage"
    nodeModules="$patchedAppDir/resources/app.asar.unpacked/node_modules"

    mkdir -p "$patchedAppDir"
    cp -a ${appimageContents}/. "$patchedAppDir"
    chmod -R u+w "$patchedAppDir"

    mkdir -p \
      "$nodeModules/@img/sharp-linux-x64" \
      "$nodeModules/@img/sharp-libvips-linux-x64"

    tar -xzf ${sharpLinuxX64} -C "$nodeModules/@img/sharp-linux-x64" --strip-components=1
    tar -xzf ${sharpLibvipsLinuxX64} -C "$nodeModules/@img/sharp-libvips-linux-x64" --strip-components=1

    asarTree="$TMPDIR/${pname}-asar"
    asar extract "$patchedAppDir/resources/app.asar" "$asarTree"
    mkdir -p "$asarTree/node_modules/@img"
    cp -a "$nodeModules/@img/sharp-linux-x64" "$asarTree/node_modules/@img/sharp-linux-x64"
    cp -a "$nodeModules/@img/sharp-libvips-linux-x64" "$asarTree/node_modules/@img/sharp-libvips-linux-x64"
    rm -f "$patchedAppDir/resources/app.asar"
    rm -rf "$patchedAppDir/resources/app.asar.unpacked"
    asar pack "$asarTree" "$patchedAppDir/resources/app.asar" --unpack '{**/*.node,**/*.so*}'

    install -Dm555 ${appimageInit} $out/share/${pname}/init
    substituteInPlace $out/share/${pname}/init \
      --replace-fail @appDir@ "$patchedAppDir"

    cp --remove-destination "$(readlink $out/bin/${pname})" $out/bin/${pname}
    chmod u+w $out/bin/${pname}
    initPath="$(sed -n 's|.*--symlink \(/nix/store/[^ ]*-openpets-2.0.6-init\) /init.*|\1|p' $out/bin/${pname})"
    substituteInPlace $out/bin/${pname} \
      --replace-fail "$initPath" "$out/share/${pname}/init"

    install -Dm444 ${appimageContents}/@open-petsdesktop.desktop \
      $out/share/applications/${pname}.desktop
    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace 'Exec=AppRun' 'Exec=${pname}' \
      --replace 'Icon=@open-petsdesktop' 'Icon=${pname}'

    install -Dm444 ${appimageContents}/@open-petsdesktop.png \
      $out/share/icons/hicolor/512x512/apps/${pname}.png
  '';

  meta = with lib; {
    description = "Tray-first desktop companion app for AI coding agents";
    homepage = "https://github.com/alvinunreal/openpets";
    changelog = "https://github.com/alvinunreal/openpets/releases/tag/v${version}";
    license = licenses.mit;
    mainProgram = pname;
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
