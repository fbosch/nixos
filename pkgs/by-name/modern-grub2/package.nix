{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  imagemagick,
}:

stdenvNoCC.mkDerivation rec {
  pname = "modern-grub2";
  version = "unstable-2023-10-15";

  src = fetchFromGitHub {
    owner = "Seven59";
    repo = "Modern-grub2";
    rev = "06e96ab54ebf36c37c2f0c8f9cb7fa57c6e93ca4";
    hash = "sha256-nKHASKDlaKy5J/PCrgvxP5e2ShoRpLxA5RoSdHJZXDQ=";
  };

  nativeBuildInputs = [ imagemagick ];

  # Configuration options
  theme = "tela"; # Options: tela, vimix, stylish, whitesur
  icon = "white"; # Options: color, white, whitesur
  screen = "1080p"; # Options: 1080p, 2k, 4k, ultrawide, ultrawide2k

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
