{ pkgs, lib, ... }:

let
  mkTheme =
    {
      url,
      name,
      description,
      homepage ? null,
      sha256 ? lib.fakeSha256,
    }:
    pkgs.stdenv.mkDerivation {
      name = name;

      src = pkgs.fetchzip {
        inherit url sha256;
        stripRoot = true;
      };

      dontBuild = true;
      dontConfigure = true;

      installPhase = ''
      mkdir -p $out/share/themes
      cp -r . $out/share/themes/${name}
      '';

      meta =
        with lib;
        {
          inherit description;
          platforms = platforms.linux;
        }
        // lib.optionalAttrs (homepage != null) { inherit homepage; };
    };

  mono-gtk-theme = mkTheme {
    url = "https://github.com/witalihirsch/Mono-gtk-theme/releases/download/1.3/MonoTheme.zip";
    name = "MonoTheme";
    description = "Mono GTK theme - Light variant";
    homepage = "https://github.com/witalihirsch/Mono-gtk-theme";
    sha256 = "sha256-gE0B9vWZTVM3yI1euv9o/vTdhhQ+JlkSwa2m+2ZDfFk=";
  };

  mono-gtk-theme-dark = mkTheme {
    url = "https://github.com/witalihirsch/Mono-gtk-theme/releases/download/1.3/MonoThemeDark.zip";
    name = "MonoThemeDark";
    description = "Mono GTK theme - Dark variant";
    homepage = "https://github.com/witalihirsch/Mono-gtk-theme";
    sha256 = "sha256-wQvRdJr6LWltnk8CMchu2y5zPXM5k7m0EOv4w4R8l9U=";
  };
in
{
  home.packages = [
    mono-gtk-theme
    mono-gtk-theme-dark
  ];
}
