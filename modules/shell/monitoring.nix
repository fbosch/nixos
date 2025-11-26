{
  flake.modules.homeManager.shell =
    { pkgs, config, ... }:
    {
      home.packages = with pkgs; [
        htop
        btop
        dust
        fastfetch
      ];

      xdg.configFile."fastfetch/logo.txt" = {
        source = ../../configs/fastfetch/nix.txt;
      };

      xdg.configFile."fastfetch/config.jsonc".text = builtins.toJSON {
        logo = {
          type = "file";
          source = "${config.xdg.configHome}/fastfetch/logo.txt";
          padding = {
            top = 1;
          };
        };
        display = {
          separator = " ";
        };
        modules = [
          "title"
          "separator"
          "os"
          "host"
          "kernel"
          "uptime"
          "packages"
          "shell"
          "display"
          "de"
          "wm"
          "wmtheme"
          "theme"
          "icons"
          "font"
          "cursor"
          "terminal"
          "terminalfont"
          "cpu"
          "gpu"
          "memory"
          "swap"
          "disk"
          "localip"
          "battery"
          "poweradapter"
          "locale"
          "break"
          "colors"
        ];
      };
    };
}
