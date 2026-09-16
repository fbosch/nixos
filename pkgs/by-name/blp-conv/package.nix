{ fetchCrate
, lib
, rustPlatform
}:

rustPlatform.buildRustPackage rec {
  pname = "blp-conv";
  version = "0.1.1";

  src = fetchCrate {
    inherit pname version;
    hash = "sha256-U3GBFhjeQzp4FygNOJmY4+aAax5RDDkTv7WW7frQtNQ=";
  };

  cargoHash = "sha256-tv23f8orTkcNKNJeHuY5qlQY+VcANeuC1C7S2xDfhmk=";

  meta = {
    description = "CLI tool to encode and decode Blizzard BLP texture format";
    homepage = "https://github.com/zloy-tulen/image-blp";
    license = lib.licenses.mit;
    mainProgram = "blp-conv";
    maintainers = [ ];
    platforms = lib.platforms.unix;
  };
}
