{ config, ... }:
let
  flakeConfig = config;
  zenwritten = flakeConfig.flake.lib.themes.zenwritten;
  inherit (zenwritten.css) base bright;
in
{
  flake.modules.nixos.desktop = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      json-glib
      libical
    ];

    services.gnome.evolution-data-server.enable = true;
  };

  flake.modules.homeManager.desktop =
    { config, pkgs, ... }:
    let
      inherit (flakeConfig.flake.lib) lazyDesktopApp;

      lazyGucharmap = lazyDesktopApp pkgs {
        pkg = pkgs.gucharmap;
        desktopItem = {
          name = "gucharmap";
          exec = "gucharmap";
          desktopName = "Character Map";
          comment = "Insert special characters into documents";
          icon = "accessories-character-map";
          terminal = false;
          startupNotify = true;
          categories = [
            "GNOME"
            "GTK"
            "Utility"
          ];
          keywords = [
            "font"
            "unicode"
          ];
        };
      };

      lazyGnomeTweaks = lazyDesktopApp pkgs {
        pkg = pkgs.gnome-tweaks;
        exe = "gnome-tweaks";
        desktopItem = {
          name = "org.gnome.tweaks";
          exec = "gnome-tweaks";
          desktopName = "Tweaks";
          comment = "Tweak advanced GNOME settings";
          icon = ./gnome-tweaks.svg;
          terminal = false;
          onlyShowIn = [
            "GNOME"
            "Unity"
            "Pantheon"
          ];
          startupNotify = true;
          startupWMClass = "gnome-tweaks";
          categories = [
            "GNOME"
            "GTK"
            "Utility"
          ];
          keywords = [
            "Settings"
            "Advanced"
            "Preferences"
            "Fonts"
            "Theme"
            "Keyboard"
          ];
        };
      };

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
      home.packages = with pkgs; [
        gtk4
        gtk4-layer-shell
        gnome-keyring
        lazyGnomeTweaks
        gnome-themes-extra
        gnome-calculator
        gnome-calendar
        gnomeExtensions.appindicator
        gnomeExtensions.blur-my-shell
        gnomeExtensions.mock-tray
        lazyGucharmap
        networkmanagerapplet
      ];

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
