{ pkgs, lib, stdenv, fetchFromGitHub, gtk3 }:

stdenv.mkDerivation rec {
  pname = "win11-icon-theme";
  version = "unstable-2024-10-16";

  src = fetchFromGitHub {
    owner = "yeyushengfan258";
    repo = "Win11-icon-theme";
    rev = "main";
    sha256 = lib.fakeSha256;
  };

  nativeBuildInputs = [ gtk3 ];

  dontDropIconThemeCache = true;

  installPhase = ''
    runHook preInstall
    
    patchShebangs install.sh
    
    mkdir -p $out/share/icons
    
    # Install default theme
    name=Win11 ./install.sh -d $out/share/icons -t default
    
    # Remove broken symlinks and caches
    find $out -xtype l -delete
    find $out -name "icon-theme.cache" -delete
    
    runHook postInstall
  '';

  meta = with lib; {
    description = "Windows 11 icon theme for Linux";
    homepage = "https://github.com/yeyushengfan258/Win11-icon-theme";
    license = licenses.gpl3;
    platforms = platforms.linux;
  };
}

