let
  baseFonts =
    pkgs: with pkgs; [
      nerd-fonts.symbols-only
      nerd-fonts.jetbrains-mono
      mononoki
      dejavu_fonts
      noto-fonts
      noto-fonts-cjk-sans
      unifont
    ];

  localFonts =
    pkgs: with pkgs.local; [
      font-fast-font
      font-zenbones
      font-babelstone-runes
      font-ionicons
    ];

  proprietaryFonts =
    pkgs:
      with pkgs.local;
      [
        font-microsoft
      ]
      ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isLinux font-apple;

in
{
  flake.modules = {
    nixos.fonts =
      { pkgs
      , lib
      , config
      , ...
      }:
      {
        fonts = {
          fontconfig.enable = true;
          fontDir.enable = true;
          packages =
            baseFonts pkgs
            ++ [
              pkgs.noto-fonts-color-emoji
              pkgs.noto-fonts-emoji-blob-bin
            ]
            ++ localFonts pkgs
            ++ lib.optionals (config.nixpkgs.config.allowUnfree or false) (proprietaryFonts pkgs);
        };
      };

    darwin.fonts =
      { pkgs
      , lib
      , config
      , ...
      }:
      let
        allowProprietary = config.nixpkgs.config.allowUnfree or false;
      in
      {
        fonts = {
          packages =
            baseFonts pkgs
            ++ [
              pkgs.noto-fonts-emoji-blob-bin
            ]
            ++ localFonts pkgs
            ++ lib.optionals allowProprietary (proprietaryFonts pkgs);
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
        allowProprietary =
          osConfig.nixpkgs.config.allowUnfree or config.nixpkgs.config.allowUnfree or false;
        installProprietaryFonts = pkgs.stdenv.hostPlatform.isLinux && allowProprietary;
        proprietaryFontsPackage = pkgs.symlinkJoin {
          name = "proprietary-fonts";
          paths = proprietaryFonts pkgs;
        };
      in
      {
        xdg.configFile."fontconfig/fonts.conf".text = builtins.readFile ./fonts.conf;

        xdg.dataFile = lib.mkIf installProprietaryFonts {
          "fonts/proprietary" = {
            source = "${proprietaryFontsPackage}/share/fonts";
            recursive = true;
          };
        };

        home.activation = lib.mkIf installProprietaryFonts {
          refreshFontCache = config.lib.dag.entryAfter [ "linkGeneration" ] ''
            ${pkgs.fontconfig}/bin/fc-cache -f "''${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
          '';
        };
      };
  };
}
