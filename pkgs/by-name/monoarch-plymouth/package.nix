{ lib
, stdenvNoCC
, fetchFromGitHub
, imagemagick
,
}:

stdenvNoCC.mkDerivation {
  pname = "monoarch-plymouth";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "iam-vasanth";
    repo = "monoarch-refined";
    rev = "v1.0.0";
    hash = "sha256-A6+Jz8AqK9IN/QnFICfWvZKA/MNDpNNVgs01AqH4P9g=";
  };

  nativeBuildInputs = [ imagemagick ];

  buildPhase = ''
    runHook preBuild

    # Resize NixOS logo to 128x128 to match the original Arch logo dimensions
    magick ${./nixos.png} -resize 128x128 monoarch-refined/images/logo.png

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/plymouth/themes/monoarch-refined
    cp -r monoarch-refined/* $out/share/plymouth/themes/monoarch-refined/

    # Fix absolute paths in .plymouth file
    substituteInPlace $out/share/plymouth/themes/monoarch-refined/monoarch-refined.plymouth \
      --replace-fail "/usr/share/plymouth/themes/monoarch-refined" "$out/share/plymouth/themes/monoarch-refined"

    runHook postInstall
  '';

  meta = {
    description = "Refined monochrome Plymouth boot theme with NixOS logo - centered layout and responsive design";
    homepage = "https://github.com/iam-vasanth/monoarch-refined";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
}
