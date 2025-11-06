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
  flake.modules.homeManager.fonts = { pkgs, ... }: {
    xdg.configFile."fontconfig/fonts.conf".text = builtins.readFile ../configs/fontconfig/fonts.conf;

    home.packages = with pkgs; [
      local.font-zenbones
      local.font-babelstone-runes
      local.font-ionicons
    ];

    home.file = {
      ".local/share/fonts/segoe-fluent-icons".source = pkgs.fetchzip {
        url = "https://download.microsoft.com/download/8/f/c/8fc7cbc3-177e-4a22-af48-2a85e1c5bffb/Segoe-Fluent-Icons.zip";
        sha256 = "sha256-MgwkgbVN8vZdZAFwG+CVYu5igkzNcg4DKLInOL1ES9A=";
        stripRoot = false;
      };

      ".local/share/fonts/tahoma.ttf".source = pkgs.fetchurl {
        url = "https://gitlab.winehq.org/wine/wine/-/raw/master/fonts/tahoma.ttf?ref_type=heads&inline=false";
        sha256 = "sha256-kPGrrU2gzgPaXSJ37nWpYAzoEtN8kOq3bgg4/6eTflU=";
      };

      ".local/share/fonts/AppleColorEmoji.ttf".source = pkgs.fetchurl {
        url = "https://github.com/samuelngs/apple-emoji-linux/releases/download/v18.4/AppleColorEmoji.ttf";
        sha256 = "sha256-pP0He9EUN7SUDYzwj0CE4e39SuNZ+SVz7FdmUviF6r0=";
      };

      ".local/share/fonts/SF-Pro-Display-Regular.otf".source = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/sahibjotsaggu/San-Francisco-Pro-Fonts/master/SF-Pro-Display-Regular.otf";
        sha256 = "sha256-fcBKwRAA91nJc6RcYQniwWQ3LbDbI91HlsiH33MEjNA=";
      };

      ".local/share/fonts/SF-Pro-Text-Regular.otf".source = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/sahibjotsaggu/San-Francisco-Pro-Fonts/master/SF-Pro-Text-Regular.otf";
        sha256 = "sha256-Ov0qyVxb/487oy8NZYZACUdnRznYV+c/TXtjlLCui3c=";
      };

      ".local/share/fonts/SF-Pro-Rounded-Regular.otf".source = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/sahibjotsaggu/San-Francisco-Pro-Fonts/master/SF-Pro-Rounded-Regular.otf";
        sha256 = "sha256-law3sWLJMN9jjLnLFJw2+HHL8fQpZsyYuA63/uGtyW4=";
      };

      ".local/share/fonts/SF-Mono-Regular.otf".source = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/supercomputra/SF-Mono-Font/master/SFMono-Regular.otf";
        sha256 = "sha256-QeZ8ae4LtKNkqYX+TaBLdhSKkG2Zj0EaDE+nnO+esI4=";
      };
    };
  };
}
