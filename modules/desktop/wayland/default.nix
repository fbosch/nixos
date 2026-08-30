_:
{
  flake.modules.homeManager.desktop =
    { pkgs, ... }:
    {
      systemd = {
        user = {
          services = {
            cliphist = {
              Unit = {
                Description = "Clipboard history service for Wayland";
                PartOf = [ "graphical-session.target" ];
                After = [ "graphical-session.target" ];
              };

              Service = {
                ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";
                Restart = "on-failure";
              };

              Install = {
                WantedBy = [ "graphical-session.target" ];
              };
            };

            wl-clip-persist = {
              Unit = {
                Description = "Persist Wayland clipboard after programs exit";
                PartOf = [ "graphical-session.target" ];
                After = [ "graphical-session.target" ];
              };

              Service = {
                ExecStart = "${pkgs.wl-clip-persist}/bin/wl-clip-persist --clipboard regular";
                Restart = "on-failure";
              };

              Install = {
                WantedBy = [ "graphical-session.target" ];
              };
            };

            autocutsel-clipboard = {
              Unit = {
                Description = "Sync X11 CLIPBOARD with PRIMARY";
                PartOf = [ "graphical-session.target" ];
                After = [ "graphical-session.target" ];
              };

              Service = {
                ExecStart = "${pkgs.autocutsel}/bin/autocutsel -selection CLIPBOARD";
                Restart = "on-failure";
              };

              Install = {
                WantedBy = [ "graphical-session.target" ];
              };
            };

            autocutsel-primary = {
              Unit = {
                Description = "Sync X11 PRIMARY with CLIPBOARD";
                PartOf = [ "graphical-session.target" ];
                After = [ "graphical-session.target" ];
              };

              Service = {
                ExecStart = "${pkgs.autocutsel}/bin/autocutsel -selection PRIMARY";
                Restart = "on-failure";
              };

              Install = {
                WantedBy = [ "graphical-session.target" ];
              };
            };

          };
        };
      };
    };
}
