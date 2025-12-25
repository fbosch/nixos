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
  screen = "ultrawide2k"; # Use ultrawide2k preset for proper 1440p scaling

  installPhase = ''
    runHook preInstall

    # Create output directory
    mkdir -p $out

    # Run the install script with ultrawide2k preset (3440x1440)
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
