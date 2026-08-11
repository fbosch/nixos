{ curl
, fetchurl
, jq
, lib
, nix
, nix-update
, stdenvNoCC
, writeShellScript
,
}:
stdenvNoCC.mkDerivation {
  pname = "hytale-launcher-flatpak";
  version = "2026.08.11-f021bf9";

  src = fetchurl {
    # Hytale publishes only the latest Flatpak; release-specific URLs expire.
    url = "https://launcher.hytale.com/builds/release/linux/amd64/hytale-launcher-latest.flatpak";
    hash = "sha256-2Zlebk51V1c6Yc7/bF5M3HfIid6GSIjfU5AY6KpXq8Q=";
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 "$src" "$out/hytale-launcher.flatpak"
    runHook postInstall
  '';

  passthru.updateScript = writeShellScript "update-hytale-launcher-flatpak" ''
    export PATH="${lib.makeBinPath [ nix ]}:$PATH"
    version="$(${curl}/bin/curl --fail --silent --show-error --location \
      https://launcher.hytale.com/version/release/launcher.json | ${jq}/bin/jq --raw-output '.version')"
    [ "$version" != "null" ] && [ -n "$version" ]

    exec ${nix-update}/bin/nix-update --flake --version "$version" hytale-launcher-flatpak
  '';

  meta = with lib; {
    description = "Official Hytale launcher Flatpak bundle";
    homepage = "https://hytale.com/";
    license = licenses.unfreeRedistributable;
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
