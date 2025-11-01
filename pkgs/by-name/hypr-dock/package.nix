{ lib
, buildGoModule
, fetchFromGitHub
, pkg-config
, gtk3
, gtk-layer-shell
}:

buildGoModule rec {
  pname = "hypr-dock";
  version = "unstable-2025-01-20";

  src = fetchFromGitHub {
    owner = "lotos-linux";
    repo = "hypr-dock";
    rev = "afc3e47715133e06e5a99cbb599ed6f6d465c62f";
    hash = "sha256-FhI0cXDSYpC3k4xvCdz/wJ4cTYtWaNScMMyw6cKmlkY=";
  };

  vendorHash = "sha256-wglfwQzDETlSuvPhC16blK7UV13+xUtn4wxrqzL/bfw=";
  proxyVendor = true;

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    gtk3
    gtk-layer-shell
  ];

  # Build from the main directory
  subPackages = [ "main" ];

  # Rename the binary from 'main' to 'hypr-dock'
  postInstall = ''
    mv $out/bin/main $out/bin/hypr-dock
    
    # Install config files to share directory
    mkdir -p $out/share/hypr-dock
    cp -r $src/configs/* $out/share/hypr-dock/
  '';

  meta = with lib; {
    description = "Interactive Dock Panel for Hyprland";
    homepage = "https://github.com/lotos-linux/hypr-dock";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
    mainProgram = "hypr-dock";
    maintainers = [ ];
  };
}
