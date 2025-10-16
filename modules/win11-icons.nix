{ pkgs, lib, ... }:

let
  win11IconTheme = pkgs.stdenv.mkDerivation rec {
    pname = "win11-icon-theme";
    version = "unstable-2024-10-16";

    src = pkgs.fetchFromGitHub {
      owner = "yeyushengfan258";
      repo = "Win11-icon-theme";
      rev = "main";
      sha256 = lib.fakeSha256;
    };

    nativeBuildInputs = [ pkgs.gtk3 ];

    dontBuild = true;
    dontDropIconThemeCache = true;

    installPhase = ''
      runHook preInstall
      
      mkdir -p $out/share/icons
      
      # Copy the icon theme directories directly
      cp -r Win11* $out/share/icons/
      
      # Remove any broken symlinks
      find $out -xtype l -delete
      
      # Update icon cache for each theme
      for theme in $out/share/icons/Win11*; do
        ${pkgs.gtk3}/bin/gtk-update-icon-cache -f -t "$theme" 2>/dev/null || true
      done
      
      runHook postInstall
    '';

    meta = with lib; {
      description = "Windows 11 icon theme for Linux";
      homepage = "https://github.com/yeyushengfan258/Win11-icon-theme";
      license = licenses.gpl3;
      platforms = platforms.linux;
    };
  };
in
{
  home.packages = [ win11IconTheme ];
}

