{ pkgs, lib, ... }:

let
  mkTheme = {
    src,
    name,
    description,
    type ? "gtk",
    homepage ? null
  }:
  let
    targetDir = if type == "gtk" then "themes" else "icons";
    
    theme = pkgs.stdenv.mkDerivation {
      name = name;
      inherit src;
      
      dontBuild = true;
      dontConfigure = true;
      
      installPhase = ''
        runHook preInstall
        
        mkdir -p $out/share/${targetDir}
        if [ -d "${name}" ]; then
          cp -r ${name} $out/share/${targetDir}/
        else
          cp -r . $out/share/${targetDir}/${name}
        fi
        
        runHook postInstall
      '';
      
      meta = with lib; {
        inherit description;
        platforms = platforms.linux;
      } // lib.optionalAttrs (homepage != null) { inherit homepage; };
    };
  in {
    derivation = theme;
    homeFile = {
      ".local/share/${targetDir}/${name}".source = "${theme}/share/${targetDir}/${name}";
    };
  };

  mkThemeFromSource = {
    owner,
    repo,
    rev,
    name,
    description,
    type ? "gtk",
    homepage ? null,
    sha256 ? lib.fakeSha256
  }:
    mkTheme {
      inherit name description type homepage;
      src = pkgs.fetchFromGitHub {
        inherit owner repo rev sha256;
      };
    };

  mkThemeFromZip = { 
    url, 
    name, 
    description,
    type ? "gtk",
    homepage ? null,
    sha256 ? lib.fakeSha256,
    stripRoot ? true
  }: 
    mkTheme {
      inherit name description type homepage;
      src = pkgs.fetchzip {
        inherit url sha256 stripRoot;
      };
    };

  themes = [
    (mkThemeFromZip {
      type = "gtk";
      url = "https://github.com/witalihirsch/Mono-gtk-theme/releases/download/1.3/MonoTheme.zip";
      name = "MonoTheme";
      description = "Mono GTK theme - Light variant";
      homepage = "https://github.com/witalihirsch/Mono-gtk-theme";
      sha256 = "sha256-gE0B9vWZTVM3yI1euv9o/vTdhhQ+JlkSwa2m+2ZDfFk=";
    })
    (mkThemeFromZip {
      type = "gtk";
      url = "https://github.com/witalihirsch/Mono-gtk-theme/releases/download/1.3/MonoThemeDark.zip";
      name = "MonoThemeDark";
      description = "Mono GTK theme - Dark variant";
      homepage = "https://github.com/witalihirsch/Mono-gtk-theme";
      sha256 = "sha256-wQvRdJr6LWltnk8CMchu2y5zPXM5k7m0EOv4w4R8l9U=";
    })
  ];
  themeHomeFiles = lib.mkMerge (map (t: t.homeFile) themes);
in
{
  gtk.enable = true;
  home.file = themeHomeFiles;
}
