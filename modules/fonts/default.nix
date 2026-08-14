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

    homeManager.fonts = {
      xdg.configFile."fontconfig/fonts.conf".text = builtins.readFile ./fonts.conf;
    };
  };
}
