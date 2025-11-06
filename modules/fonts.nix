let
  proprietaryFonts = [
    {
      name = "AppleColorEmoji.ttf";
      url = "https://github.com/samuelngs/apple-emoji-linux/releases/download/v18.4/AppleColorEmoji.ttf";
    }
    {
      name = "segmdl2.ttf";
      url = "https://download.microsoft.com/download/8/f/c/8fc7cbc3-177e-4a22-af48-2a85e1c5bffb/Segoe-Fluent-Icons.zip";
    }
    {
      name = "tahoma.ttf";
      url = "https://gitlab.winehq.org/wine/wine/-/raw/master/fonts/tahoma.ttf?ref_type=heads&inline=false";
    }
    {
      name = "SF-Pro-Display-Regular.otf";
      url = "https://raw.githubusercontent.com/sahibjotsaggu/San-Francisco-Pro-Fonts/master/SF-Pro-Display-Regular.otf";
    }
    {
      name = "SF-Pro-Text-Regular.otf";
      url = "https://raw.githubusercontent.com/sahibjotsaggu/San-Francisco-Pro-Fonts/master/SF-Pro-Text-Regular.otf";
    }
    {
      name = "SF-Pro-Rounded-Regular.otf";
      url = "https://raw.githubusercontent.com/sahibjotsaggu/San-Francisco-Pro-Fonts/master/SF-Pro-Rounded-Regular.otf";
    }
    {
      name = "SF-Mono-Regular.otf";
      url = "https://raw.githubusercontent.com/supercomputra/SF-Mono-Font/master/SFMono-Regular.otf";
    }
  ];
in
{
  flake.modules.nixos.fonts = { pkgs, ... }: {
    fonts = {
      fontconfig.enable = true;
      fontDir.enable = true;
      packages = with pkgs; [
        nerd-fonts.symbols-only
        nerd-fonts.jetbrains-mono
      ];
    };
  };
  flake.modules.homeManager.fonts = { pkgs, lib, config, ... }: {
    xdg.configFile."fontconfig/fonts.conf".text = builtins.readFile ../configs/fontconfig/fonts.conf;

    home.packages = with pkgs; [
      local.font-zenbones
      local.font-babelstone-runes
      local.font-ionicons
      curl
      unzip
      fontconfig
    ];

    home.activation.installProprietaryFonts = lib.mkIf (config.nixpkgs.config.allowUnfree or false) (lib.hm.dag.entryAfter [ "writeBoundary" ] (
      let
        curlBin = "${pkgs.curl}/bin/curl";
        unzipBin = "${pkgs.unzip}/bin/unzip";
        fcCacheBin = "${pkgs.fontconfig}/bin/fc-cache";
        dlLines = lib.concatStringsSep "\n" (map
          (font:
            if lib.hasSuffix ".zip" font.url then ''
              if [ ! -f "$fonts_dir/${font.name}" ]; then
                tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
                ${curlBin} -fL "${font.url}" -o "$tmp/archive.zip"
                ${unzipBin} -jo "$tmp/archive.zip" -d "$fonts_dir"
              fi
            '' else ''
              dl "${font.url}" "$fonts_dir/${font.name}"
            ''
          )
          proprietaryFonts);
      in
      ''
        set -euo pipefail

        fonts_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
        mkdir -p "$fonts_dir"

        dl() {
          local url="$1" dest="$2"
          [ -f "$dest" ] || ${curlBin} -fL "$url" -o "$dest"
        }

        # Download listed proprietary fonts (.zip handled specially)
        ${dlLines}

        ${fcCacheBin} -f "$fonts_dir" || ${fcCacheBin} -f
      ''
    ));
  };
}
