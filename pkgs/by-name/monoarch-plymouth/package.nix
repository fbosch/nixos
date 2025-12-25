{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  imagemagick,
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

    # Modify script to use centered 1920x1080 viewport on ultrawide displays
    substituteInPlace $out/share/plymouth/themes/monoarch-refined/monoarch-refined.script \
      --replace-fail 'screen.w = Window.GetWidth();' 'actual.w = Window.GetWidth(); screen.w = (actual.w > 1920) ? 1920 : actual.w; screen.offset.x = (actual.w - screen.w) / 2;' \
      --replace-fail 'screen.h = Window.GetHeight();' 'actual.h = Window.GetHeight(); screen.h = (actual.h > 1080) ? 1080 : actual.h; screen.offset.y = (actual.h - screen.h) / 2;' \
      --replace-fail 'screen.half.w = Window.GetWidth() / 2;' 'screen.half.w = screen.w / 2;' \
      --replace-fail 'screen.half.h = Window.GetHeight() / 2;' 'screen.half.h = screen.h / 2;' \
      --replace-fail 'logo.x = Window.GetWidth() / 2 - logo.image.GetWidth() / 2;' 'logo.x = screen.offset.x + screen.w / 2 - logo.image.GetWidth() / 2;' \
      --replace-fail 'logo.y = Window.GetHeight() / 2 - logo.image.GetHeight() / 2 - Window.GetHeight() * 0.05;' 'logo.y = screen.offset.y + screen.h / 2 - logo.image.GetHeight() / 2 - screen.h * 0.05;' \
      --replace-fail 'spinner.x = Window.GetWidth() / 2 - spinner.image.GetWidth() / 2;' 'spinner.x = screen.offset.x + screen.w / 2 - spinner.image.GetWidth() / 2;' \
      --replace-fail 'spinner.y = logo.y + logo.image.GetHeight() + Window.GetHeight() * 0.03;' 'spinner.y = logo.y + logo.image.GetHeight() + screen.h * 0.03;' \
      --replace-fail 'logo.y = Window.GetHeight() / 2 - logo.image.GetHeight() / 2;' 'logo.y = screen.offset.y + screen.h / 2 - logo.image.GetHeight() / 2;' \
      --replace-fail 'startPos = screen.half.w - totalWidth / 2;' 'startPos = screen.offset.x + screen.half.w - totalWidth / 2;' \
      --replace-fail 'prompt.sprite.SetX(screen.half.w - prompt.image.GetWidth() / 2);' 'prompt.sprite.SetX(screen.offset.x + screen.half.w - prompt.image.GetWidth() / 2);' \
      --replace-fail 'prompt.sprite.SetY(screen.h - 4 * prompt.image.GetHeight());' 'prompt.sprite.SetY(screen.offset.y + screen.h - 4 * prompt.image.GetHeight());' \
      --replace-fail 'bullets[i].sprite.SetY(screen.h - 2 * bullet.image.GetHeight());' 'bullets[i].sprite.SetY(screen.offset.y + screen.h - 2 * bullet.image.GetHeight());'

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
