let
  zenwritten = import ../../../assets/themes/zenwritten.nix;
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
        gnome-tweaks
        gnome-themes-extra
        gnome-calculator
        gnome-calendar
        gnomeExtensions.appindicator
        gnomeExtensions.blur-my-shell
        gnomeExtensions.mock-tray
        gucharmap
        networkmanagerapplet
      ];

      dconf.settings = {
        "org/gnome/desktop/interface" = {
          monospace-font-name = "SF Mono 11";
          gtk-theme = "MonoThemeDark";
          icon-theme = "Win11-dark";
          cursor-theme = "WinSur-white-cursors";
          font-name = "SF Pro Display 11";
          text-scaling-factor = 1.0;
          color-scheme = "prefer-dark";
        };
      };

      xdg.configFile."gtk-4.0/gtk.css" = {
        force = true;
        text = ''
          * {
            font-family: "SF Pro Display", sans-serif;
          }

          :root {
            --document-font-family: "SF Pro Display", sans-serif;
          }

          @media (prefers-color-scheme: dark) {
            :root {
              --accent-blue: ${base.sky};
              --accent-teal: ${base.sky};
              --accent-green: ${base.leaf};
              --accent-yellow: ${base.wood};
              --accent-orange: ${base.wood};
              --accent-red: ${base.rose};
              --accent-pink: ${base.blossom};
              --accent-purple: ${base.blossom};
              --accent-slate: ${base.stone};
              --accent-bg-color: ${base.sky};
              --accent-color: ${bright.sky};
              --accent-fg-color: #ffffff;
              --destructive-bg-color: ${base.rose};
              --destructive-color: ${bright.rose};
              --destructive-fg-color: #ffffff;
              --success-bg-color: ${base.leaf};
              --success-color: ${bright.leaf};
              --success-fg-color: #ffffff;
              --warning-bg-color: ${base.wood};
              --warning-color: ${bright.wood};
              --warning-fg-color: rgba(0, 0, 0, 0.8);
              --error-bg-color: ${base.rose};
              --error-color: ${bright.rose};
              --error-fg-color: #ffffff;
              --window-bg-color: ${base.background};
              --view-bg-color: ${base.background};
              --headerbar-bg-color: ${base.surface};
              --sidebar-bg-color: ${base.surface};
              --sidebar-backdrop-color: ${base.surface};
              --secondary-sidebar-bg-color: ${base.surface};
              --secondary-sidebar-backdrop-color: ${base.surface};
              --dialog-bg-color: ${base.surface};
              --popover-bg-color: ${base.surface};
              --thumbnail-bg-color: ${base.surface};
              --overview-bg-color: ${base.surface};
            }
          }
        '';
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
