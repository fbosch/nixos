{
  flake.modules.nixos.fonts = { pkgs, ... }: {
    fonts = {
      fontconfig.enable = true;
      fontDir.enable = true;
      packages = with pkgs; [
        nerd-fonts.symbols-only
        nerd-fonts.jetbrains-mono
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
        noto-fonts-emoji-blob-bin
      ];
    };
  };
  flake.modules.homeManager.fonts = { pkgs, lib, config, ... }:
    let
      allowProprietary = config.nixpkgs.config.allowUnfree or false;

      proprietaryFontsPackage =
        if !allowProprietary then null
        else
          let
            fonts = [
              {
                fileName = "AppleColorEmoji.ttf";
                src = pkgs.fetchurl {
                  url = "https://github.com/samuelngs/apple-emoji-linux/releases/download/v18.4/AppleColorEmoji.ttf";
                  sha256 = "sha256-pP0He9EUN7SUDYzwj0CE4e39SuNZ+SVz7FdmUviF6r0=";
                };
              }
              {
                fileName = "segmdl2.ttf";
                src = pkgs.fetchzip {
                  url = "https://download.microsoft.com/download/8/f/c/8fc7cbc3-177e-4a22-af48-2a85e1c5bffb/Segoe-Fluent-Icons.zip";
                  sha256 = "sha256-hyCLlUOtFzg6GxspL+kTPFRrogsryCSXW+NypIUbPkQ=";
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
                fileName = "SF-Mono-Regular.otf";
                src = pkgs.fetchurl {
                  url = "https://raw.githubusercontent.com/supercomputra/SF-Mono-Font/master/SFMono-Regular.otf";
                  sha256 = "sha256-QeZ8ae4LtKNkqYX+TaBLdhSKkG2Zj0EaDE+nnO+esI4=";
                };
              }
            ];

            installCommands = lib.concatStringsSep "\n" (map
              (font:
                let
                  srcPath =
                    if font ? sourcePath then "${font.src}/${font.sourcePath}" else "${font.src}";
                in
                ''install -Dm644 ${lib.escapeShellArg srcPath} "$out/${font.fileName}"''
              )
              fonts);
          in
          pkgs.runCommandLocal "proprietary-fonts"
            {
              preferLocalBuild = true;
              allowSubstitutes = false;
            } ''
            set -euo pipefail
            mkdir -p "$out"
            ${installCommands}
          '';
    in
    {
      xdg.configFile."fontconfig/fonts.conf".text = builtins.readFile ../configs/fontconfig/fonts.conf;

      home.packages = with pkgs; [
        local.font-zenbones
        local.font-babelstone-runes
        local.font-ionicons
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
}
