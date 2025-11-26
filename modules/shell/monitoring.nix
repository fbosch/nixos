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

      xdg.configFile."fastfetch/config.jsonc".text = ''
        {
          "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
          "logo": {
            "type": "file-raw",
            "source": "${config.xdg.configHome}/fastfetch/logo.txt",
            "padding": {
              "top": 1,
              "right": 3
            }
          },
          "display": {
            "separator": " "
          },
          "modules": [
            "title",
            "separator",
            "os",
            "host",
            "kernel",
            "uptime",
            "packages",
            "shell",
            "de",
            "wm",
            "terminal",
            "cpu",
            "gpu",
            "memory",
            "disk",
            "break",
            "colors"
          ]
        }
      '';
    };
}
