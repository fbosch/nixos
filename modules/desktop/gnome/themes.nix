{
  flake.modules.nixos.desktop =
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
          mkdir -p $out/share/themes/MonoTheme
          cp -r . $out/share/themes/MonoTheme/
        '';
      };

      monoThemeDark = pkgs.stdenv.mkDerivation {
        name = "MonoThemeDark";
        src = pkgs.fetchzip {
          url = "https://github.com/witalihirsch/Mono-gtk-theme/releases/download/1.3/MonoThemeDark.zip";
          sha256 = "sha256-wQvRdJr6LWltnk8CMchu2y5zPXM5k7m0EOv4w4R8l9U=";
        };
        patches = [ ./patches/mono-theme-dark-zenwritten.patch ];
        dontBuild = true;
        installPhase = ''
          mkdir -p $out/share/themes/MonoThemeDark
          cp -r . $out/share/themes/MonoThemeDark/
        '';
      };

      adwGtk3Zenwritten = pkgs.adw-gtk3.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./patches/adw-gtk3-zenwritten.patch ];
      });
    in
    {
      environment.systemPackages = [
        monoTheme
        monoThemeDark
        pkgs.gtk4
        adwGtk3Zenwritten
        pkgs.colloid-gtk-theme
      ];
    };
}
