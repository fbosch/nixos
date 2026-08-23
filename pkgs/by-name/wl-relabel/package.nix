{ fetchCrate
, lib
, rustPlatform
,
}:

rustPlatform.buildRustPackage rec {
  pname = "wl-relabel";
  version = "0.1.1";

  src = fetchCrate {
    inherit pname version;
    hash = "sha256-xRJOeyAIrcn3lURyjfBvwxQ4w4Qh2i0qAKLzujSPLpM=";
  };

  cargoHash = "sha256-XKiNzsLJBEbW+WJeMHOxc29ND9gSV3IY2d4mbCknwp8=";

  meta = {
    description = "Wayland proxy that conditionally rewrites window app IDs";
    homepage = "https://github.com/valentin-morice/wl-relabel";
    license = with lib.licenses; [
      asl20
      mit
    ];
    mainProgram = "wl-relabel";
    maintainers = [ ];
    platforms = lib.platforms.linux;
  };
}
