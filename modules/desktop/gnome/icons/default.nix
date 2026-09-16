{ config, ... }:
let
  composeIconThemeFor = config.flake.lib.iconOverrides.composeIconTheme;
in
{
  flake.modules.nixos.desktop =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;
      composeIconTheme = composeIconThemeFor pkgs;



      win11IconsBase = pkgs.stdenv.mkDerivation {
        name = "Win11";
        src = pkgs.fetchFromGitHub {
          owner = "yeyushengfan258";
          repo = "Win11-icon-theme";
          rev = "a5b460a407da143b32f19a503d7fcebb3edf2371";
          sha256 = "sha256-+GtOkOVSWlNTdKSs0R86LhnpbBZ21Y0ML3V8pwDUUSc=";
        };
        nativeBuildInputs = [ pkgs.gtk3 ];
        dontBuild = true;
        dontFixup = true;
        installPhase = ''
          runHook preInstall
          patchShebangs install.sh
          mkdir -p $out/share/icons
          DESTDIR="$out" ./install.sh -d $out/share/icons -n Win11
          find $out/share/icons -xtype l -delete
          for dir in $out/share/icons/*/; do
            if [ -f "$dir/index.theme" ]; then
              ${pkgs.gtk3}/bin/gtk-update-icon-cache -f -t "$dir" || true
            fi
          done
          runHook postInstall
        '';
      };

      confluxIconsBase = pkgs.stdenv.mkDerivation {
        name = "Conflux";
        src = pkgs.fetchFromGitHub {
          owner = "MoshiurRahmanAdib";
          repo = "Conflux-Icon-Theme";
          rev = "d64da34e6e81dd9a08ca068d55038b0578b1ba98";
          sha256 = "sha256-jmm+k7S1w02iEbUhviyKViBxbdJFnusvSKVA6hA1l0A=";
        };
        nativeBuildInputs = [ pkgs.gtk3 ];
        dontBuild = true;
        dontFixup = true;
        installPhase = ''
          runHook preInstall
          mkdir -p $out/share/icons/Conflux
          cp -ar apps apps@2x devices devices@2x emblems emblems@2x index.theme mimes mimes@2x places places@2x preferences preferences@2x status status@2x $out/share/icons/Conflux/
          ${pkgs.gtk3}/bin/gtk-update-icon-cache -f -t $out/share/icons/Conflux || true
          runHook postInstall
        '';
      };

      lactIcon = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/tsora1603/pixora-icons/446edba0937fca3593a0da08cf4307eeff3e0d7d/pixora/scalable/apps/lact.svg";
        hash = "sha256-dKP35GxVJXhbDDQd4/e2KWggWH87SVvZr0/9U5iBt7A=";
      };

      panStartIcon = pkgs.writeText "pan-start-symbolic.svg" ''
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
          <path d="M10.5 3 5.5 8l5 5z" fill="currentColor"/>
        </svg>
      '';

      panEndIcon = pkgs.writeText "pan-end-symbolic.svg" ''
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
          <path d="M5.5 3 10.5 8l-5 5z" fill="currentColor"/>
        </svg>
      '';

      panDownIcon = pkgs.writeText "pan-down-symbolic.svg" ''
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
          <path d="M3 5.5 8 10.5l5-5z" fill="currentColor"/>
        </svg>
      '';

      gnomeCalendarIcons = pkgs.runCommand "gnome-calendar-icons" { } ''
        mkdir -p $out
        tar -xf ${pkgs.gnome-calendar.src} --strip-components=1 -C $out
      '';

      confluxIconOverrides = [
        {
          name = "go-down-symbolic";
          source = "${pkgs.adwaita-icon-theme}/share/icons/Adwaita/symbolic/actions/go-down-symbolic.svg";
          sizes = [ "symbolic" ];
          context = "Actions";
        }
        {
          name = "go-next-symbolic";
          source = "${pkgs.adwaita-icon-theme}/share/icons/Adwaita/symbolic/actions/go-next-symbolic.svg";
          sizes = [ "symbolic" ];
          context = "Actions";
        }
        {
          name = "go-next-symbolic-rtl";
          source = "${pkgs.adwaita-icon-theme}/share/icons/Adwaita/symbolic/actions/go-next-symbolic-rtl.svg";
          sizes = [ "symbolic" ];
          context = "Actions";
        }
        {
          name = "go-previous-symbolic";
          source = "${pkgs.adwaita-icon-theme}/share/icons/Adwaita/symbolic/actions/go-previous-symbolic.svg";
          sizes = [ "symbolic" ];
          context = "Actions";
        }
        {
          name = "go-previous-symbolic-rtl";
          source = "${pkgs.adwaita-icon-theme}/share/icons/Adwaita/symbolic/actions/go-previous-symbolic-rtl.svg";
          sizes = [ "symbolic" ];
          context = "Actions";
        }
        {
          name = "pan-start-symbolic";
          source = panStartIcon;
          sizes = [ "symbolic" ];
          context = "Actions";
        }
        {
          name = "pan-end-symbolic";
          source = panEndIcon;
          sizes = [ "symbolic" ];
          context = "Actions";
        }
        {
          name = "pan-down-symbolic";
          source = panDownIcon;
          sizes = [ "symbolic" ];
          context = "Actions";
        }
        {
          name = "calendar-agenda-symbolic";
          source = "${gnomeCalendarIcons}/src/gui/icons/calendar-agenda-symbolic.svg";
          sizes = [ "symbolic" ];
          context = "Actions";
        }
        {
          name = "checkmark-small-symbolic";
          source = "${gnomeCalendarIcons}/src/gui/icons/checkmark-small-symbolic.svg";
          sizes = [ "symbolic" ];
          context = "Actions";
        }
        {
          name = "clock-alt-symbolic";
          source = "${gnomeCalendarIcons}/src/gui/icons/clock-alt-symbolic.svg";
          sizes = [ "symbolic" ];
          context = "Actions";
        }
        {
          name = "loupe-large-symbolic";
          source = "${gnomeCalendarIcons}/src/gui/icons/loupe-large-symbolic.svg";
          sizes = [ "symbolic" ];
          context = "Actions";
        }
        {
          name = "x-office-calendar-symbolic";
          source = "${pkgs.adwaita-icon-theme}/share/icons/Adwaita/symbolic/mimetypes/x-office-calendar-symbolic.svg";
          sizes = [ "symbolic" ];
          context = "Mimetypes";
        }
        {
          name = "folder";
          useBuiltinFrom = "places/scalable/folder";
          sizes = [
            "16"
            "22"
            "24"
            "symbolic"
          ];
          context = "Places";
        }
        {
          name = "folder-open";
          useBuiltinFrom = "places/scalable/folder-open";
          sizes = [
            "16"
            "22"
            "24"
            "symbolic"
          ];
          context = "Places";
        }
        {
          name = "user-desktop";
          useBuiltinFrom = "places/scalable/user-desktop";
          sizes = [
            "16"
            "22"
            "24"
            "symbolic"
          ];
          context = "Places";
        }
        {
          name = "folder-music";
          useBuiltinFrom = "places/scalable/folder-music";
          sizes = [
            "16"
            "22"
            "24"
            "symbolic"
          ];
          context = "Places";
        }
        {
          name = "folder-pictures";
          useBuiltinFrom = "places/scalable/folder-pictures";
          sizes = [
            "16"
            "22"
            "24"
            "symbolic"
          ];
          context = "Places";
        }
        {
          name = "folder-publicshare";
          useBuiltinFrom = "places/scalable/folder-publicshare";
          sizes = [
            "16"
            "22"
            "24"
            "symbolic"
          ];
          context = "Places";
        }
        {
          name = "folder-templates";
          useBuiltinFrom = "places/scalable/folder-templates";
          sizes = [
            "16"
            "22"
            "24"
            "symbolic"
          ];
          context = "Places";
        }
        {
          name = "folder-videos";
          useBuiltinFrom = "places/scalable/folder-videos";
          sizes = [
            "16"
            "22"
            "24"
            "symbolic"
          ];
          context = "Places";
        }
        {
          name = "folder-download";
          useBuiltinFrom = "places/scalable/folder-download";
          sizes = [
            "16"
            "22"
            "24"
            "symbolic"
          ];
          context = "Places";
        }
        {
          name = "folder-documents";
          useBuiltinFrom = "places/scalable/folder-documents";
          sizes = [
            "16"
            "22"
            "24"
            "symbolic"
          ];
          context = "Places";
        }
        {
          name = "discord";
          source = ./discord.svg;
          sizes = [ "scalable" ];
          context = "Applications";
        }
        {
          name = "io.Astal.ags";
          useBuiltin = "preferences-system";
          sizes = [ "scalable" ];
          context = "Applications";
        }
        {
          name = "chatgpt";
          source = ./codex.png;
          extension = "png";
          sizes = [ "scalable" ];
          context = "Applications";
        }
        {
          name = "io.github.ilya_zlobintsev.LACT";
          source = lactIcon;
          sizes = [ "scalable" ];
          context = "Applications";
        }
      ];

      confluxIcons = composeIconTheme {
        name = "Conflux";
        base = {
          package = confluxIconsBase;
          theme = "Conflux";
        };
        replace.Status = {
          package = win11IconsBase;
          theme = "Win11-dark";
        };
        fallbacks = [
          {
            package = win11IconsBase;
            theme = "Win11";
          }
          {
            package = pkgs.adwaita-icon-theme;
            theme = "Adwaita";
          }
          {
            package = pkgs.kdePackages.breeze-icons;
            theme = "breeze";
          }
          {
            package = pkgs.hicolor-icon-theme;
            theme = "hicolor";
          }
        ];
        iconOverrides = confluxIconOverrides;
      };

      win11Icons = composeIconTheme {
        name = "Win11";
        base = {
          package = win11IconsBase;
          theme = "Win11";
        };
        iconOverrides = confluxIconOverrides;
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
        confluxIcons
        win11Icons
        pkgs.simp1e-cursors
        we10xIcons
        mkosBigSurIcons
      ];
    };
}
