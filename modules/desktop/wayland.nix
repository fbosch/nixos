{ inputs, ... }:
{
  flake.modules.nixos.desktop =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        xrdb
        xhost
        xrandr
        xprop
        xwininfo
      ];
    };

  flake.modules.homeManager.desktop =
    { pkgs, lib, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
    in
    {
      home.packages = lib.optionals pkgs.stdenv.isLinux (
        let
          agsPackage = inputs.ags.packages.${system}.default;
        in
        [
          # waycorner
          # rofi
          pkgs.xwayland
          pkgs.xwayland-satellite
          pkgs.setxkbmap
          agsPackage
          pkgs.wev
          pkgs.nwg-look
          pkgs.nwg-displays
          pkgs.wlr-randr
          pkgs.wl-clipboard
          pkgs.xclip
          pkgs.xsel
          pkgs.autocutsel
          pkgs.cliphist
          pkgs.wl-clip-persist
          pkgs.wtype
          pkgs.xdotool
          pkgs.waybar
          pkgs.swaynotificationcenter
          pkgs.libnotify
          pkgs.swayosd
          pkgs.gsettings-desktop-schemas
        ]
      );

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

            gamescope-clipboard-sync = {
              Unit = {
                Description = "Sync clipboard between Wayland and Gamescope Xwayland";
                PartOf = [ "graphical-session.target" ];
                After = [ "graphical-session.target" ];
              };

              Service = {
                ExecStart = "${pkgs.bash}/bin/bash %h/.config/hypr/scripts/gamescope-clipboard-sync.sh";
                Restart = "on-failure";
                RestartSec = "1";
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
