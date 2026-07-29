{ fetchFromGitHub
, lib
, rustPlatform
,
}:

rustPlatform.buildRustPackage rec {
  pname = "filterway";
  version = "unstable-2026-07-20";

  src = fetchFromGitHub {
    owner = "andrewbaxter";
    repo = "filterway";
    rev = "32488c97ff766ecfa2bb2b171284c9ef527ccc29";
    hash = "sha256-O5FT9VAUvcpaf6beCYTx19TPcL0YFTyceHtl5BYvFLY=";
  };

  cargoHash = "sha256-kvd/iNvhj5RvCYVQZrhOqe+AmPqV6Jo4sswqI30n/b0=";
  RUSTC_BOOTSTRAP = 1;

  meta = {
    description = "Wayland socket proxy that filters and modifies requests";
    homepage = "https://github.com/andrewbaxter/filterway";
    license = lib.licenses.isc;
    mainProgram = "filterway";
    maintainers = [ ];
    platforms = lib.platforms.linux;
  };
}
