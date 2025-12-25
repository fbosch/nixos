{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  imagemagick,
}:

stdenvNoCC.mkDerivation rec {
  pname = "modern-grub2";
  version = "unstable-2024-04-12";

  src = fetchFromGitHub {
    owner = "Seven59";
    repo = "Modern-grub2";
    rev = "b732fe3fad5b30dd55b108826943285656e5921c";
    hash = "sha256-8efXbfV/Ri86vqtGRBJbcaFSQFigFp4/edImnR9aWTc=";
  };

  nativeBuildInputs = [ imagemagick ];

  # Configuration options
  theme = "whitesur"; # Options: tela, vimix, stylish, whitesur
  icon = "whitesur"; # Options: color, white, whitesur
  screen = "ultrawide"; # Options: 1080p, 2k, 4k, ultrawide, ultrawide2k

  installPhase = ''
    runHook preInstall

    # Create output directory
    mkdir -p $out

    # Run the install script to generate the theme
    bash ./install.sh \
      --generate $out \
      --screen ${screen} \
      --theme ${theme} \
      --icon ${icon}

    runHook postInstall
  '';

  meta = with lib; {
    description = "Modern Design theme for Grub2";
    homepage = "https://github.com/Seven59/Modern-grub2";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
