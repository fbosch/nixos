{
  flake.modules = {
    nixos.fonts =
      { pkgs, ... }:
      {
        fonts = {
          fontconfig.enable = true;
          fontDir.enable = true;
          packages = with pkgs; [
            nerd-fonts.symbols-only
            nerd-fonts.jetbrains-mono
            dejavu_fonts
            noto-fonts
            noto-fonts-cjk-sans
            noto-fonts-color-emoji
            noto-fonts-emoji-blob-bin
            unifont
          ];
        };
      };

    darwin.fonts =
      { pkgs, ... }:
      {
        fonts = {
          packages = with pkgs; [
            nerd-fonts.symbols-only
            nerd-fonts.jetbrains-mono
            dejavu_fonts
            noto-fonts
            noto-fonts-cjk-sans
            noto-fonts-color-emoji
            noto-fonts-emoji-blob-bin
            unifont
          ];
        };
      };

    homeManager.fonts =
      { pkgs
      , lib
      , config
      , osConfig
      , ...
      }:
      let
        # Check if we're on Darwin (macOS already has SF Pro and Apple Color Emoji)
        isDarwin = osConfig.networking.hostName or null != null && pkgs.stdenv.isDarwin;

        allowProprietary =
          osConfig.nixpkgs.config.allowUnfree or config.nixpkgs.config.allowUnfree or false;

        proprietaryFontsPackage =
          if !allowProprietary then
            null
          else
            let
              # Base fonts for all platforms
              baseFonts = [
                {
                  fileName = "segmdl2.ttf";
                  src = pkgs.fetchzip {
                    url = "https://download.microsoft.com/download/8/f/c/8fc7cbc3-177e-4a22-af48-2a85e1c5bffb/Segoe-Fluent-Icons.zip";
                    sha256 = "sha256-MgwkgbVN8vZdZAFwG+CVYu5igkzNcg4DKLInOL1ES9A=";
                    stripRoot = false;
                  };
                  sourcePath = "Segoe Fluent Icons.ttf";
                }
                {
                  fileName = "tahoma.ttf";
                  src = pkgs.fetchurl {
                    url = "https://gitlab.winehq.org/wine/wine/-/raw/master/fonts/tahoma.ttf?ref_type=heads&inline=false";
                    sha256 = "sha256-kPGrrU2gzgPaXSJ37nWpYAzoEtN8kOq3bgg4/6eTflU=";
                  };
                }
              ];

              # Fonts only for non-Darwin (Linux)
              # macOS already includes SF Pro and Apple Color Emoji natively
              linuxOnlyFonts = [
                {
                  fileName = "AppleColorEmoji.ttf";
                  src = pkgs.fetchurl {
                    url = "https://github.com/samuelngs/apple-emoji-linux/releases/download/v18.4/AppleColorEmoji.ttf";
                    sha256 = "sha256-pP0He9EUN7SUDYzwj0CE4e39SuNZ+SVz7FdmUviF6r0=";
                  };
                }
                {
                  fileName = "SF-Pro-Display-Regular.otf";
                  src = pkgs.fetchurl {
                    url = "https://raw.githubusercontent.com/sahibjotsaggu/San-Francisco-Pro-Fonts/master/SF-Pro-Display-Regular.otf";
                    sha256 = "sha256-fcBKwRAA91nJc6RcYQniwWQ3LbDbI91HlsiH33MEjNA=";
                  };
                }
                {
                  fileName = "SF-Pro-Text-Regular.otf";
                  src = pkgs.fetchurl {
                    url = "https://raw.githubusercontent.com/sahibjotsaggu/San-Francisco-Pro-Fonts/master/SF-Pro-Text-Regular.otf";
                    sha256 = "sha256-Ov0qyVxb/487oy8NZYZACUdnRznYV+c/TXtjlLCui3c=";
                  };
                }
                {
                  fileName = "SF-Pro-Rounded-Regular.otf";
                  src = pkgs.fetchurl {
                    url = "https://raw.githubusercontent.com/sahibjotsaggu/San-Francisco-Pro-Fonts/master/SF-Pro-Rounded-Regular.otf";
                    sha256 = "sha256-law3sWLJMN9jjLnLFJw2+HHL8fQpZsyYuA63/uGtyW4=";
                  };
                }
                {
                  fileName = "SF-Pro-Rounded-Medium.otf";
                  src = pkgs.fetchurl {
                    url = "https://raw.githubusercontent.com/sahibjotsaggu/San-Francisco-Pro-Fonts/master/SF-Pro-Rounded-Medium.otf";
                    sha256 = "sha256-pTyu3elDUk/6ImW24eJNJ3t2kSMPfYB1XLQZ167yj70=";
                  };
                }
                {
                  fileName = "SF-Pro-Rounded-Semibold.otf";
                  src = pkgs.fetchurl {
                    url = "https://raw.githubusercontent.com/sahibjotsaggu/San-Francisco-Pro-Fonts/master/SF-Pro-Rounded-Semibold.otf";
                    sha256 = "sha256-iqm39XBGVQ78JzkPNOnYjn+SUz6jpC0v9pv4UuHl1Oc=";
                  };
                }
                {
                  fileName = "SF-Pro-Rounded-Bold.otf";
                  src = pkgs.fetchurl {
                    url = "https://raw.githubusercontent.com/sahibjotsaggu/San-Francisco-Pro-Fonts/master/SF-Pro-Rounded-Bold.otf";
                    sha256 = "sha256-eLDNVmeashZbIpUiPWUZq84TnbB5VJO/Y3b23ZtQBBs=";
                  };
                }
                {
                  fileName = "SF-Mono-Regular.otf";
                  src = pkgs.fetchurl {
                    url = "https://raw.githubusercontent.com/supercomputra/SF-Mono-Font/master/SFMono-Regular.otf";
                    sha256 = "sha256-QeZ8ae4LtKNkqYX+TaBLdhSKkG2Zj0EaDE+nnO+esI4=";
                  };
                }
              ];

              fonts = baseFonts ++ (if isDarwin then [ ] else linuxOnlyFonts);

              installCommands = lib.concatStringsSep "\n" (
                map
                  (
                    font:
                    let
                      srcPath = if font ? sourcePath then "${font.src}/${font.sourcePath}" else "${font.src}";
                    in
                    ''install -Dm644 ${lib.escapeShellArg srcPath} "$out/${font.fileName}"''
                  )
                  fonts
              );
            in
            pkgs.runCommandLocal "proprietary-fonts"
              {
                preferLocalBuild = true;
                allowSubstitutes = false;
              }
              ''
                set -euo pipefail
                mkdir -p "$out"
                ${installCommands}
              '';
      in
      {
        xdg.configFile."fontconfig/fonts.conf".text = builtins.readFile ../configs/fontconfig/fonts.conf;

        home.packages =
          [
            (pkgs.callPackage ../pkgs/by-name/font-zenbones/package.nix { })
            (pkgs.callPackage ../pkgs/by-name/font-babelstone-runes/package.nix { })
            (pkgs.callPackage ../pkgs/by-name/font-ionicons/package.nix { })
          ];

        xdg.dataFile = lib.mkIf allowProprietary {
          "fonts/proprietary" = {
            source = proprietaryFontsPackage;
            recursive = true;
          };
        };

        home.activation.refreshFontCache = lib.mkIf allowProprietary (
          lib.hm.dag.entryAfter [ "linkGeneration" ] ''
            set -euo pipefail

            fonts_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
            ${pkgs.fontconfig}/bin/fc-cache -f "$fonts_dir"
          ''
        );
      };
  };
}
