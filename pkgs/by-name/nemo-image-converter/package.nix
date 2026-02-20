{ lib
, stdenv
, fetchFromGitHub
, meson
, ninja
, pkg-config
, nemo
, glib
, gtk3
, gettext
, wrapGAppsHook3
,
}:

stdenv.mkDerivation {
  pname = "nemo-image-converter";
  version = "6.6.0";

  src = fetchFromGitHub {
    owner = "linuxmint";
    repo = "nemo-extensions";
    rev = "3bdb43428eedc5527d7f9ecb27227f8d101271dc";
    hash = "sha256-tXeMkaCYnWzg+6ng8Tyg4Ms1aUeE3xiEkQ3tKEX6Vv8=";
  };

  sourceRoot = "source/nemo-image-converter";

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    gettext
    wrapGAppsHook3
  ];

  buildInputs = [
    nemo
    glib
    gtk3
  ];

  # libnemo_extension_dir is read from the pkg-config variable, which points
  # into nemo's store path. Override it to install into $out instead.
  postPatch = ''
    substituteInPlace src/meson.build \
      --replace-fail "install_dir: libnemo_extension_dir" \
                     "install_dir: '${placeholder "out"}/${nemo.extensiondir}'"
  '';

  meta = {
    description = "Nemo extension to rotate or resize images";
    homepage = "https://github.com/linuxmint/nemo-extensions";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
  };
}
