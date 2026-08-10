{ config, ... }:
let
  flakeConfig = config;
  zenwritten = flakeConfig.flake.lib.themes.zenwritten;
  inherit (zenwritten.css) base bright;
in
{
  flake.modules.homeManager.desktop = { pkgs, ... }: {
    dconf.settings = {
      "org/gnome/desktop/interface" = {
        monospace-font-name = "SF Mono 11";
        gtk-theme = "MonoThemeDark";
        icon-theme = "Win11-dark";
        cursor-theme = "WinSur-white-cursors";
        cursor-size = 24;
        font-name = "SF Pro Display 11";
        text-scaling-factor = 1.0;
        color-scheme = "prefer-dark";
      };
    };

    xdg.configFile = {
      "gtk-4.0/gtk.css".source = pkgs.replaceVars ./css/gtk-4.css {
        baseSky = base.sky;
        baseLeaf = base.leaf;
        baseWood = base.wood;
        baseRose = base.rose;
        baseBlossom = base.blossom;
        baseStone = base.stone;
        baseBackground = base.background;
        baseSurface = base.surface;
        brightSky = bright.sky;
        brightRose = bright.rose;
        brightLeaf = bright.leaf;
        brightWood = bright.wood;
      };

      "gtk-3.0/settings.ini".source = ./config/gtk-3-settings.ini;
      "gtk-4.0/settings.ini".source = ./config/gtk-4-settings.ini;
    };
  };
}
