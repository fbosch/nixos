{ config, ... }:
{
  flake.modules.nixos.desktop = {
    imports = config.flake.lib.resolve [ "themes" ];
  };

  flake.modules.homeManager.desktop = _: {
    dconf.settings = {
      "org/gnome/desktop/interface" = {
        monospace-font-name = "SF Mono 11";
        gtk-theme = "MonoThemeDark";
        icon-theme = "Win11";
        cursor-theme = "WinSur-white-cursors";
        font-name = "SF Pro Display 11";
        text-scaling-factor = 1.0;
        color-scheme = "prefer-dark";
      };
    };
  };
}
