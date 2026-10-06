{ lib
, stdenv
, fetchFromGitHub
, meson
, ninja
, pkg-config
, nemo
, glib
, gtk3
, imagemagick
, gettext
, wrapGAppsHook3
,
}:

stdenv.mkDerivation {
  pname = "nemo-image-converter";
  version = "6.7.0-unstable";

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
    imagemagick
  ];

  # libnemo_extension_dir is read from pkg-config and points into nemo's store path.
  # Override it to install into $out instead, and bind the converter to its Nix path.
  postPatch = ''
    substituteInPlace src/meson.build \
      --replace-fail "install_dir: libnemo_extension_dir" \
                     "install_dir: '${placeholder "out"}/${nemo.extensiondir}'"
    substituteInPlace src/nemo-image-resizer.c \
      --replace-fail 'argv[0] = "/usr/bin/convert";' \
                     'argv[0] = "${imagemagick}/bin/convert";'
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    plugin="$out/${nemo.extensiondir}/libnemo-image-converter.so"
    grep -aFq '${imagemagick}/bin/convert' "$plugin"

    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT
    ${imagemagick}/bin/convert -size 8x6 xc:red "$tmpdir/input.png"
    ${imagemagick}/bin/convert "$tmpdir/input.png" -resize 4x3 "$tmpdir/output.png"
    test "$(
      ${imagemagick}/bin/identify -format '%wx%h' "$tmpdir/output.png"
    )" = "4x3"

    runHook postInstallCheck
  '';

  meta = {
    description = "Nemo extension to rotate or resize images";
    homepage = "https://github.com/linuxmint/nemo-extensions";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
  };
}
