{ pkgs, lib, ... }:

let
  mkTheme = { 
    url, 
    name, 
    description,
    type ? "gtk",
    homepage ? null,
    sha256 ? lib.fakeSha256,
    stripRoot ? true,
    buildScript ? null,
    buildScriptArgs ? ""
  }: 
  let
    targetDir = if type == "gtk" then "themes" else "icons";
    
    theme = pkgs.stdenv.mkDerivation {
      name = name;
      
      src = pkgs.fetchzip {
        inherit url sha256 stripRoot;
      };
      
      nativeBuildInputs = lib.optionals (buildScript != null) [ pkgs.bash ];
      
      dontBuild = true;
      dontConfigure = true;
      
      installPhase = if buildScript != null then ''
        mkdir -p $out/share/${targetDir}
        ${pkgs.bash}/bin/bash ${buildScript} --dest $out/share/${targetDir} ${buildScriptArgs}
      '' else ''
        mkdir -p $out/share/${targetDir}
        if [ -d "${name}" ]; then
          cp -r ${name} $out/share/${targetDir}/
        else
          cp -r . $out/share/${targetDir}/${name}
        fi
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

  themes = [
    (mkTheme {
      type = "gtk";
      url = "https://github.com/witalihirsch/Mono-gtk-theme/releases/download/1.3/MonoTheme.zip";
      name = "MonoTheme";
      description = "Mono GTK theme - Light variant";
      homepage = "https://github.com/witalihirsch/Mono-gtk-theme";
      sha256 = "sha256-gE0B9vWZTVM3yI1euv9o/vTdhhQ+JlkSwa2m+2ZDfFk=";
    })
    (mkTheme {
      type = "gtk";
      url = "https://github.com/witalihirsch/Mono-gtk-theme/releases/download/1.3/MonoThemeDark.zip";
      name = "MonoThemeDark";
      description = "Mono GTK theme - Dark variant";
      homepage = "https://github.com/witalihirsch/Mono-gtk-theme";
      sha256 = "sha256-wQvRdJr6LWltnk8CMchu2y5zPXM5k7m0EOv4w4R8l9U=";
    })
    (mkTheme {
      type = "icon";
      url = "https://github.com/yeyushengfan258/Win11-icon-theme/archive/refs/heads/main.tar.gz";
      name = "Win11";
      description = "Windows 11 icon theme for Linux";
      homepage = "https://github.com/yeyushengfan258/Win11-icon-theme";
      sha256 = lib.fakeSha256;
      buildScript = "install.sh";
      buildScriptArgs = "--theme default";
    })
  ];
  themeHomeFiles = lib.mkMerge (map (t: t.homeFile) themes);
in
{
  gtk.enable = true;
  home.file = themeHomeFiles;
}
