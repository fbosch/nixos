{ config, ... }:
let
  packagesFor = pkgs: [ pkgs.gnome-calendar ];
  denmarkHolidaysColor = config.flake.lib.themes.zenwritten.css.base.rose;
in
{
  flake.modules = {
    nixos.desktop = { pkgs, ... }: {
      environment.systemPackages = [ pkgs.libical ] ++ packagesFor pkgs;
      services.gnome.evolution-data-server.enable = true;
    };

    homeManager.desktop =
      { config, pkgs, ... }:
      let
        denmarkHolidaysSource = pkgs.writeText "denmark-holidays.source" ''
          [Data Source]
          DisplayName=Denmark Holidays
          Enabled=true
          Parent=webcal-stub

          [Calendar]
          BackendName=webcal
          Color=${denmarkHolidaysColor}
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
  };
}
