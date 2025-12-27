_: {
  # NixOS module: Install GTK themes system-wide
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
        dontBuild = true;
        installPhase = ''
          mkdir -p $out/share/themes/MonoThemeDark
          cp -r . $out/share/themes/MonoThemeDark/
        '';
      };

      win11Icons = pkgs.stdenv.mkDerivation {
        name = "Win11";
        src = pkgs.fetchFromGitHub {
          owner = "yeyushengfan258";
          repo = "Win11-icon-theme";
          rev = "main";
          sha256 = "sha256-+GtOkOVSWlNTdKSs0R86LhnpbBZ21Y0ML3V8pwDUUSc=";
        };
        nativeBuildInputs = [ pkgs.gtk3 ];
        dontBuild = true;
        # The install script creates symlinks that may reference missing color variants
        # This is expected behavior for icon themes with multiple variants
        dontFixup = true;
        installPhase = ''
          runHook preInstall

          patchShebangs install.sh
          mkdir -p $out/share/icons
          
          # Run the install script with default options
          DESTDIR="$out" ./install.sh -d $out/share/icons -n Win11

          # Remove broken symlinks that reference missing color variants
          find $out/share/icons -xtype l -delete

          # Run icon cache update
          for dir in $out/share/icons/*/; do
            if [ -f "$dir/index.theme" ]; then
              ${pkgs.gtk3}/bin/gtk-update-icon-cache -f -t "$dir" || true
            fi
          done

          runHook postInstall
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
          mkdir -p $out/share/icons
          cp -ar dist/. $out/share/icons/WinSur-white-cursors/
        '';
      };

      we10xIcons = pkgs.stdenv.mkDerivation {
        name = "We10X";
        src = pkgs.fetchFromGitHub {
          owner = "yeyushengfan258";
          repo = "We10X-icon-theme";
          rev = "master";
          sha256 = "sha256-EPhq5WCFdF76lQMGC4GhwSh9Gu9uyL8KwvLYxP8FUxs=";
        };
        dontBuild = true;
        installPhase = ''
          mkdir -p $out/share/icons
          cp -ar src/. $out/share/icons/We10X/
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
          mkdir -p $out/share/icons
          cp -ar . $out/share/icons/Mkos-Big-Sur/
        '';
      };
    in
    {
      environment.systemPackages = [
        monoTheme
        monoThemeDark
        win11Icons
        winsurCursors
        we10xIcons
        mkosBigSurIcons
        pkgs.gtk4
        pkgs.adw-gtk3
        pkgs.colloid-gtk-theme
      ];
    };

  # Home Manager module: Configure GTK settings
  flake.modules.homeManager.desktop =
    { ... }:
    {
      dconf.settings = {
        "org/gnome/desktop/interface" = {
          monospace-font-name = "SF Mono 11";
          gtk-theme = "MonoThemeDark";
          icon-theme = "Win11";
          cursor-theme = "WinSur-white-cursors";
          font-name = "SF Pro Display 11";
          text-scaling-factor = 1.0;
          color-scheme = "prefer-dark";
        };
      };
    };
}
