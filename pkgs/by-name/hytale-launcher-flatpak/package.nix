{ curl
, fetchurl
, jq
, lib
, nix
, nix-update
, stdenvNoCC
, writeShellApplication
,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "hytale-launcher-flatpak";
  version = "2026.07.29-8228f98";

  src = fetchurl {
    url = "https://launcher.hytale.com/builds/release/linux/amd64/hytale-launcher-${finalAttrs.version}.flatpak";
    hash = "sha256-bBoeuEqeA7Ju1EPinr7GRlBDVcBESchMfS6T4vvPSHM=";
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 "$src" "$out/hytale-launcher.flatpak"
    runHook postInstall
  '';

  passthru.updateScript = writeShellApplication {
    name = "update-hytale-launcher-flatpak";
    runtimeInputs = [
      curl
      jq
      nix
      nix-update
    ];
    text = ''
      version="$(curl --fail --silent --show-error --location \
        https://launcher.hytale.com/version/release/launcher.json | jq --raw-output '.version')"
      [ "$version" != "null" ] && [ -n "$version" ]

      exec nix-update --flake --version "$version" hytale-launcher-flatpak
    '';
  };

  meta = with lib; {
    description = "Official Hytale launcher Flatpak bundle";
    homepage = "https://hytale.com/";
    license = licenses.unfreeRedistributable;
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
})
