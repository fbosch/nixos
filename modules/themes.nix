{ pkgs, ... }:

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

  themes = [
    { name = "MonoTheme"; source = monoTheme; }
    { name = "MonoThemeDark"; source = monoThemeDark; }
  ];

  icons = [
    { name = "Win11"; source = win11Icons; }
    { name = "WinSur-white-cursors"; source = winsurCursors; }
  ];

  copyItems = dir: items: pkgs.lib.concatMapStringsSep "\n" (item: ''
    if [ -d "${item.source}" ]; then
      rm -rf "${dir}/${item.name}"
      cp -rL "${item.source}" "${dir}/${item.name}"
    fi
  '') items;
in
{
  # copy instead of symlink to be able to theme flatpak apps
  home.activation.copyThemes = ''
    THEMES_DIR="$HOME/.local/share/themes"
    ICONS_DIR="$HOME/.local/share/icons"

    mkdir -p "$THEMES_DIR"
    mkdir -p "$ICONS_DIR"

    ${copyItems "$THEMES_DIR" themes}
    ${copyItems "$ICONS_DIR" icons}
  '';
}
