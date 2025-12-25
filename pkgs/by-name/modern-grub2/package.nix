{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  imagemagick,
}:

stdenvNoCC.mkDerivation rec {
  pname = "modern-grub2";
  version = "unstable-2024-12-25";

  src = fetchFromGitHub {
    owner = "vinceliuice";
    repo = "grub2-themes";
    rev = "80dd04ddf3ba7b284a7b1a5df2b1e95ee2aad606";
    hash = "sha256-tKU+vq34KHu/A2wD7WdgP5A4/RCmSD8hB0TyQAUlixA=";
  };

  nativeBuildInputs = [ imagemagick ];

  # Configuration options
  theme = "whitesur"; # Options: tela, vimix, stylish, whitesur
  icon = "whitesur"; # Options: color, white, whitesur
  customResolution = "3440x1440"; # Custom resolution for ultrawide display

  installPhase = ''
    runHook preInstall

    # Create output directory
    mkdir -p $out

    # Run the install script to generate the theme with custom resolution
    bash ./install.sh \
      --generate $out \
      --custom-resolution ${customResolution} \
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
