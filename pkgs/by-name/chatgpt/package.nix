{ lib
, stdenv
, stdenvNoCC
, callPackage
, coreutils
, curl
, fetchurl
, gnused
, gzip
, autoPatchelfHook
, makeWrapper
, nix
, nix-update
, wrapGAppsHook3
, dpkg
, alsa-lib
, at-spi2-atk
, at-spi2-core
, atk
, cairo
, cups
, dbus
, dconf
, expat
, gdk-pixbuf
, glib
, gtk3
, libgbm
, libnotify
, libusb1
, libx11
, libxcb
, libxcomposite
, libxdamage
, libxext
, libxfixes
, libxkbcommon
, libxrandr
, nspr
, nss
, pango
, qt6
, systemdLibs
, bubblewrap
, libGL
, libpulseaudio
, libsecret
, nodejs-slim
, pipewire
, ripgrep
, tectonic-unwrapped
, vulkan-loader
, writeShellScript
, xdg-utils
,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "chatgpt";
  version = "26.803.81509";

  src = fetchurl {
    url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_${finalAttrs.version}_amd64.deb";
    hash = "sha256-qb+Ro2j598Tuo4CCqfuPtGuNAFtxmm13FdLloZgsOOs=";
  };

  strictDeps = true;
  __structuredAttrs = true;

  # autoPatchelf moves PT_INTERP beyond detect-libc's 2 KiB scan. Its
  # process.report fallback trips Electron's CFI, so use the glibc watcher.
  postPatch = ''
    grep -aFq 'const family = familySync();' usr/lib/chatgpt/resources/app.asar
    sed -i "s|const family = familySync();|const family = 'glibc'     ;|" usr/lib/chatgpt/resources/app.asar
  '';

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
    makeWrapper
    qt6.wrapQtAppsHook
    wrapGAppsHook3
  ];

  buildInputs = [
    (lib.getLib stdenv.cc.cc)
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dconf
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    libgbm
    libnotify
    libusb1
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    nspr
    nss
    pango
    qt6.qtbase
    systemdLibs
  ];

  dontWrapGApps = true;
  dontWrapQtApps = true;
  sourceRoot = "root";

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    cp -r usr/* "$out"

    # Remove the unused Qt 5 fallback shim.
    rm -f "$out/lib/chatgpt/libqt5_shim.so"

    # This glibc desktop package uses neither musl nor Android variants.
    rm -f \
      "$out/lib/chatgpt/resources/app.asar.unpacked/node_modules/@worklouder/device-kit-oai/node_modules/@worklouder/wl-device-kit/node_modules/serialport/node_modules/@serialport/bindings-cpp/prebuilds/"{linux-*/node.napi.musl.node,android-*/node.napi.*.node} \
      "$out/lib/chatgpt/resources/app.asar.unpacked/node_modules/@worklouder/device-kit-oai/node_modules/@worklouder/wl-device-kit/node_modules/node-hid/prebuilds/"{HID,HID_hidraw}-linux-*-musl/node-napi-v4.node \
      "$out/lib/chatgpt/resources/plugins/openai-bundled/plugins/"{browser,chrome}"/scripts/node_modules/classic-level/prebuilds/"{linux-*/classic-level.musl.node,android-*/classic-level.*.node}

    ln -sf ${lib.getExe tectonic-unwrapped} "$out/lib/chatgpt/resources/plugins/openai-bundled/plugins/latex/bin/tectonic"
    ln -sf ${lib.getExe ripgrep} "$out/lib/chatgpt/resources/rg"
    ln -sf ${lib.getExe nodejs-slim} "$out/lib/chatgpt/resources/cua_node/bin/node"

    install -Dm755 ${lib.getExe finalAttrs.passthru.launcher} "$out/bin/chatgpt"

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/bin/chatgpt" \
      "''${gappsWrapperArgs[@]}" \
      "''${qtWrapperArgs[@]}" \
      --set CHATGPT_EXECUTABLE "$out/lib/chatgpt/ChatGPT" \
      --set CHATGPT_RESOURCES_SOURCE "$out/lib/chatgpt/resources" \
      --set CHATGPT_RESOURCES_CACHE_KEY "''${out##*/}" \
      --prefix PATH : ${lib.makeBinPath [
        nodejs-slim
        xdg-utils
        bubblewrap
      ]} \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [
        libGL
        libnotify
        libpulseaudio
        libsecret
        pipewire
        vulkan-loader
      ]} \
      --set-default CODEX_BROWSER_USE_NODE_PATH ${lib.getExe nodejs-slim} \
      --set-default NODE_REPL_NODE_PATH ${lib.getExe nodejs-slim}
  '';

  dontStrip = true;

  passthru = {
    launcher = callPackage ./launcher.nix { };
    updateScript = writeShellScript "update-chatgpt" ''
      export PATH="${lib.makeBinPath [ nix ]}:$PATH"

      base_url="https://persistent.oaistatic.com/codex-app-prod/linux/deb"
      packages_url="$base_url/dists/stable/main/binary-amd64/Packages.gz"
      metadata="$(${curl}/bin/curl --fail --location --silent --show-error "$packages_url" \
        | ${gzip}/bin/gzip --decompress --stdout)"

      get_field() {
        local field="$1"
        printf '%s\n' "$metadata" \
          | ${gnused}/bin/sed -n "s/^$field: //p" \
          | ${coreutils}/bin/head -n 1
      }

      package="$(get_field Package)"
      architecture="$(get_field Architecture)"
      version="$(get_field Version)"
      filename="$(get_field Filename)"

      if [ "$package" != "chatgpt" ] || [ "$architecture" != "amd64" ]; then
        echo "Unexpected ChatGPT package metadata: package=$package architecture=$architecture" >&2
        exit 1
      fi

      expected_filename="pool/main/c/chatgpt/chatgpt_''${version}_amd64.deb"
      if [ "$filename" != "$expected_filename" ]; then
        echo "Unexpected ChatGPT package path: $filename" >&2
        exit 1
      fi

      if [ "''${UPDATE_NIX_OLD_VERSION:-}" = "$version" ]; then
        echo "chatgpt is already up to date" >&2
        exit 0
      fi

      exec ${nix-update}/bin/nix-update --flake --version "$version" chatgpt
    '';
  };

  meta = with lib; {
    description = "Desktop application for ChatGPT";
    homepage = "https://learn.chatgpt.com/docs/linux/linux-app";
    changelog = "https://learn.chatgpt.com/docs/changelog";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    mainProgram = "chatgpt";
    maintainers = [ ];
  };
})
