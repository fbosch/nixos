{
  flake.modules.homeManager.gtk = { pkgs, ... }:
    let
      monoTheme = pkgs.stdenv.mkDerivation {
        name = "MonoTheme";
        src = pkgs.fetchzip {
          url = "https://github.com/witalihirsch/Mono-gtk-theme/releases/download/1.3/MonoTheme.zip";
          sha256 = "sha256-/Ysak/WeWY4+svCu3yhi/blfcUsSnGOrWn8/YCyNTYM=";
        };
        dontBuild = true;
        installPhase = ''
          mkdir -p $out
          cp -r . $out/
        '';
      };

      monoThemeDark = pkgs.stdenv.mkDerivation {
        name = "MonoThemeDark";
        src = pkgs.fetchzip {
          url = "https://github.com/witalihirsch/Mono-gtk-theme/releases/download/1.3/MonoThemeDark.zip";
          sha256 = "sha256-wQvRdJr6LWltnk8CMchu2y5zPXM5k7m0EOv4w4R8l9U=";
        };
        dontBuild = true;
        installPhase = ''
          mkdir -p $out
          cp -r . $out/
        '';
      };

      win11Icons = pkgs.stdenv.mkDerivation {
        name = "Win11";
        src = pkgs.fetchFromGitHub {
          owner = "yeyushengfan258";
          repo = "Win11-icon-theme";
          rev = "main";
          sha256 = "sha256-vjW2vPIr2FPnlP0inyvn9vxOy62HDmHATqNKUMBf25I=";
        };
        dontBuild = true;
        installPhase = ''
          mkdir -p $out
          cp -ar src/. $out/
        '';
      };

      winsurCursors = pkgs.stdenv.mkDerivation {
        name = "WinSur-white-cursors";
        src = pkgs.fetchFromGitHub {
          owner = "yeyushengfan258";
          repo = "WinSur-white-cursors";
          rev = "master";
          sha256 = "sha256-EdliC9jZcFmRBq3KCNiev5ECyCWdNlb0lA9c2/JVqwo=";
        };
        dontBuild = true;
        installPhase = ''
          mkdir -p $out
          cp -ar dist/. $out/
        '';
      };

      we10xIcons = pkgs.stdenv.mkDerivation {
        name = "We10X";
        src = pkgs.fetchFromGitHub {
          owner = "yeyushengfan258";
          repo = "We10X-icon-theme";
          rev = "master";
          sha256 = "sha256-nSZm0YjLmMejiMLCkHJZszbCaOaJU7yi6ijK0caVL5g=";
        };
        dontBuild = true;
        installPhase = ''
          mkdir -p $out
          cp -ar src/. $out/
        '';
      };

      mkosBigSurIcons = pkgs.stdenv.mkDerivation {
        name = "Mkos-Big-Sur";
        src = pkgs.fetchFromGitHub {
          owner = "zayronxio";
          repo = "Mkos-Big-Sur";
          rev = "29772d17999a5c771873420f3379888d66d2e3c1";
          sha256 = "sha256-8qAADWjAvhIlq1uxGIfvfguc90FivXKPToKW1dxPpDs=";
        };
        dontBuild = true;
        dontFixup = true;
        installPhase = ''
          mkdir -p $out
          cp -ar . $out/
        '';
      };
    in
    {
      home.file = {
        ".local/share/themes/MonoTheme".source = monoTheme;
        ".local/share/themes/MonoThemeDark".source = monoThemeDark;
        ".local/share/icons/Win11".source = win11Icons;
        ".local/share/icons/WinSur-white-cursors".source = winsurCursors;
        ".local/share/icons/We10X".source = we10xIcons;
        ".local/share/icons/Mkos-Big-Sur".source = mkosBigSurIcons;
      };
    };
}
