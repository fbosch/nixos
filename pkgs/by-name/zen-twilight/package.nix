{ lib
, stdenv
, fetchurl
, wrapFirefox
, wrapGAppsHook3
, autoPatchelfHook
, alsa-lib
, curl
, dbus-glib
, gtk3
, libxtst
, libva
, pciutils
, pipewire
, adwaita-icon-theme
, patchelfUnstable
, ...
}:

let
  pname = "zen-twilight";
  version = "1.20t-2026-05-05";
  binaryName = "zen-twilight";
  libName = "zen-twilight-${version}";
  unwrapped = stdenv.mkDerivation {
    pname = "zen-twilight-unwrapped";
    inherit version;

    src = fetchurl {
      url = "https://github.com/zen-browser/desktop/releases/download/twilight-1/zen.linux-x86_64.tar.xz";
      hash = "sha256-6ZWTyH4f9VQmy7XpbM1iiNAqzCchlW0vvRjQq1MpzvE=";
    };

    nativeBuildInputs = [
      wrapGAppsHook3
      autoPatchelfHook
      patchelfUnstable
    ];

    buildInputs = [
      gtk3
      adwaita-icon-theme
      alsa-lib
      dbus-glib
      libxtst
    ];

    runtimeDependencies = [
      curl
      libva.out
      pciutils
    ];

    appendRunpaths = [ "${pipewire}/lib" ];
    patchelfFlags = [ "--no-clobber-old-sections" ];

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/lib/${libName}" "$out/bin"
      cp -r . "$out/lib/${libName}"
      ln -s "$out/lib/${libName}/zen" "$out/bin/${binaryName}"
      install -Dm444 "$out/lib/${libName}/browser/chrome/icons/default/default128.png" \
        "$out/share/icons/hicolor/128x128/apps/${pname}.png"

      runHook postInstall
    '';

    passthru = {
      inherit binaryName libName gtk3;
      applicationName = "Zen Twilight";
      ffmpegSupport = true;
      gssSupport = true;
    };

    meta = {
      description = "Nightly experimental build of Zen Browser";
      homepage = "https://zen-browser.app/";
      changelog = "https://github.com/zen-browser/desktop/releases/tag/twilight-1";
      license = lib.licenses.mpl20;
      platforms = [ "x86_64-linux" ];
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    };
  };
in
wrapFirefox unwrapped {
  inherit pname version;
  icon = pname;
  wmClass = "zen-twilight";
  inherit libName;
}
