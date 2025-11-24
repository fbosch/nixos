{ lib
, stdenvNoCC
, fetchFromGitLab
, substituteAll
}:

stdenvNoCC.mkDerivation rec {
  pname = "primitivistical-grub";
  version = "unstable-2019-04-17";

  src = fetchFromGitLab {
    owner = "fffred";
    repo = "primitivistical-grub";
    rev = "528923042a1e46e934f11a4383c5fdffad3263f5";
    hash = "sha256-IX3kQdVZx5TFZ1VrQ0UGcRAXtD6mLXwLFDLRO5xGL9I=";
  };

  # DPI scaling factor (1-4, where 1 = standard DPI)
  scaling = 1;

  # Calculated dimensions based on scaling
  iconWidth = 25 * scaling;
  iconHeight = 25 * scaling;
  itemIconSpace = 7 * scaling;
  itemHeight = 30 * scaling;
  itemSpacing = 5 * scaling;
  fontSize = 13 * scaling;

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # Create output directory
    mkdir -p $out

    # Copy theme files
    cp -r Primitivistical/* $out/

    # Copy the appropriate font based on scaling
    cp "Fonts/DejaVuSans${toString fontSize}.pf2" $out/DejaVuSans.pf2

    # Substitute placeholders in theme.txt
    substituteInPlace $out/theme.txt \
      --replace-fail "ICON_WIDTH" "${toString iconWidth}" \
      --replace-fail "ICON_HEIGHT" "${toString iconHeight}" \
      --replace-fail "ITEM_ICON_SPACE" "${toString itemIconSpace}" \
      --replace-fail "ITEM_HEIGHT" "${toString itemHeight}" \
      --replace-fail "ITEM_SPACING" "${toString itemSpacing}"

    runHook postInstall
  '';

  meta = with lib; {
    description = "A minimalist GRUB theme with a dark background";
    homepage = "https://gitlab.com/fffred/primitivistical-grub";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
