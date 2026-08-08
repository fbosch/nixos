{ config, ... }:
let
  flakeConfig = config;
  zenwritten = flakeConfig.flake.lib.themes.zenwritten;
  inherit (zenwritten.css) base bright;
  packagesFor = import ./_packages.nix {
    inherit (flakeConfig.flake.lib) lazyDesktopApp;
  };
in
{
  flake.modules.nixos.desktop = { pkgs, ... }: {
    environment.systemPackages =
      (with pkgs; [
        json-glib
        libical
      ])
      ++ packagesFor pkgs;

    services.gnome.evolution-data-server.enable = true;
  };

  flake.modules.homeManager.desktop =
    { config, pkgs, ... }:
    let
      denmarkHolidaysSource = pkgs.writeText "denmark-holidays.source" ''
        [Data Source]
        DisplayName=Denmark Holidays
        Enabled=true
        Parent=webcal-stub

        [Calendar]
        BackendName=webcal
        Color=${zenwritten.css.base.rose}
        Selected=true

        [Authentication]
        Host=www.thunderbird.net
        Method=none
        Port=443
        ProxyUid=system-proxy
        RememberPassword=false
        User=

        [Refresh]
        Enabled=true
        IntervalMinutes=1440

        [Security]
        Method=tls

        [WebDAV Backend]
        ResourcePath=/media/caldata/autogen/DenmarkHolidays.ics
        ResourceQuery=

        [Offline]
        StaySynchronized=true
      '';
    in
    {
      home.packages = packagesFor pkgs;

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

      home.activation.denmarkHolidaysCalendar = config.lib.dag.entryAfter [ "writeBoundary" ] ''
        source_dir="$HOME/.config/evolution/sources"
        source_file="$source_dir/denmark-holidays.source"

        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$source_dir"
        if [ -L "$source_file" ]; then
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm "$source_file"
        fi
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0644 ${denmarkHolidaysSource} "$source_file"
      '';
    };
}
