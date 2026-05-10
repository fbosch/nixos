{
  flake.modules.nixos.desktop =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;

      applyIconOverrides =
        { basePackage
        , overrides
        , themeName
        ,
        }:
        pkgs.stdenv.mkDerivation {
          name = "${basePackage.name}-with-overrides";
          inherit (basePackage) src;

          nativeBuildInputs = (basePackage.nativeBuildInputs or [ ]) ++ [ pkgs.xmlstarlet ];
          dontBuild = basePackage.dontBuild or true;
          dontFixup = basePackage.dontFixup or false;

          installPhase =
            basePackage.installPhase or ''
              runHook preInstall
              mkdir -p $out
              cp -r . $out/
              runHook postInstall
            '';

          postInstall = (basePackage.postInstall or "") + ''
            ${lib.concatMapStringsSep "\n" (override: ''
              for theme_dir in $out/share/icons/${themeName}*; do
                ${lib.concatMapStringsSep "\n" (size: ''
                  size_dir="$theme_dir/${override.context}/${size}"
                  if [ -d "$size_dir" ]; then
                    ${
                      if override ? useBuiltin then
                        ''
                          if [ -f "$size_dir/${override.useBuiltin}.svg" ]; then
                            rm -f "$size_dir/${override.name}.svg"
                            cp -f "$size_dir/${override.useBuiltin}.svg" "$size_dir/${override.name}.svg"
                          fi
                        ''
                      else if override ? useBuiltinFrom then
                        ''
                          source_icon="$theme_dir/${override.useBuiltinFrom}.svg"
                          if [ -f "$source_icon" ]; then
                            target_size=""
                            case "${size}" in
                              16) target_size="16" ;;
                              22) target_size="22" ;;
                              24) target_size="24" ;;
                              32) target_size="32" ;;
                              48) target_size="48" ;;
                              64) target_size="64" ;;
                              scalable) target_size="64" ;;
                              symbolic) target_size="16" ;;
                              *) target_size="16" ;;
                            esac

                            rm -f "$size_dir/${override.name}.svg"
                            cp "$source_icon" "$size_dir/${override.name}.svg"

                            if [ "${size}" != "scalable" ]; then
                              ${pkgs.xmlstarlet}/bin/xmlstarlet ed -L \
                                -u "//*[local-name()='svg']/@width" -v "$target_size" \
                                -u "//*[local-name()='svg']/@height" -v "$target_size" \
                                "$size_dir/${override.name}.svg" 2>/dev/null || true
                            fi
                          fi
                        ''
                      else
                        ''
                          if [ -f "${override.source}" ]; then
                            target_size=""
                            case "${size}" in
                              16) target_size="16" ;;
                              22) target_size="22" ;;
                              24) target_size="24" ;;
                              32) target_size="32" ;;
                              48) target_size="48" ;;
                              64) target_size="64" ;;
                              scalable) target_size="64" ;;
                              symbolic) target_size="16" ;;
                              *) target_size="16" ;;
                            esac

                            rm -f "$size_dir/${override.name}.svg"
                            cp "${override.source}" "$size_dir/${override.name}.svg"

                            if [ "${size}" != "scalable" ]; then
                              ${pkgs.xmlstarlet}/bin/xmlstarlet ed -L \
                                -u "//*[local-name()='svg']/@width" -v "$target_size" \
                                -u "//*[local-name()='svg']/@height" -v "$target_size" \
                                "$size_dir/${override.name}.svg" 2>/dev/null || true
                            fi
                          fi
                        ''
                    }
                  fi
                '') override.sizes}
              done
            '') overrides}

            if command -v gtk-update-icon-cache &> /dev/null; then
              for dir in $out/share/icons/*/; do
                if [ -f "$dir/index.theme" ]; then
                  ${pkgs.gtk3}/bin/gtk-update-icon-cache -f -t "$dir" || true
                fi
              done
            fi
          '';
        };

      win11IconsBase = pkgs.stdenv.mkDerivation {
        name = "Win11";
        src = pkgs.fetchFromGitHub {
          owner = "yeyushengfan258";
          repo = "Win11-icon-theme";
          rev = "main";
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

      lactIcon = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/tsora1603/pixora-icons/446edba0937fca3593a0da08cf4307eeff3e0d7d/pixora/scalable/apps/lact.svg";
        hash = "sha256-dKP35GxVJXhbDDQd4/e2KWggWH87SVvZr0/9U5iBt7A=";
      };

      win11IconOverrides = [
        {
          name = "go-down-symbolic";
          source = "${pkgs.adwaita-icon-theme}/share/icons/Adwaita/symbolic/actions/go-down-symbolic.svg";
          sizes = [ "symbolic" ];
          context = "actions";
        }
        {
          name = "go-next-symbolic";
          source = "${pkgs.adwaita-icon-theme}/share/icons/Adwaita/symbolic/actions/go-next-symbolic.svg";
          sizes = [ "symbolic" ];
          context = "actions";
        }
        {
          name = "go-next-symbolic-rtl";
          source = "${pkgs.adwaita-icon-theme}/share/icons/Adwaita/symbolic/actions/go-next-symbolic-rtl.svg";
          sizes = [ "symbolic" ];
          context = "actions";
        }
        {
          name = "go-previous-symbolic";
          source = "${pkgs.adwaita-icon-theme}/share/icons/Adwaita/symbolic/actions/go-previous-symbolic.svg";
          sizes = [ "symbolic" ];
          context = "actions";
        }
        {
          name = "go-previous-symbolic-rtl";
          source = "${pkgs.adwaita-icon-theme}/share/icons/Adwaita/symbolic/actions/go-previous-symbolic-rtl.svg";
          sizes = [ "symbolic" ];
          context = "actions";
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
          context = "places";
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
          context = "places";
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
          context = "places";
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
          context = "places";
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
          context = "places";
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
          context = "places";
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
          context = "places";
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
          context = "places";
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
          context = "places";
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
          context = "places";
        }
        {
          name = "discord";
          source = ../../../assets/icons/discord.svg;
          sizes = [ "scalable" ];
          context = "apps";
        }
        {
          name = "io.github.ilya_zlobintsev.LACT";
          source = lactIcon;
          sizes = [ "scalable" ];
          context = "apps";
        }
      ];

      win11Icons = applyIconOverrides {
        basePackage = win11IconsBase;
        overrides = win11IconOverrides;
        themeName = "Win11";
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
        win11Icons
        winsurCursors
        we10xIcons
        mkosBigSurIcons
      ];
    };
}
