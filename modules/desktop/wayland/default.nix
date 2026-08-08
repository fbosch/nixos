{ config, inputs, ... }:
let
  packagesFor = import ./_packages.nix {
    inherit inputs;
    inherit (config.flake.lib) lazyDesktopApp;
  };
in
{
  flake.modules.nixos.desktop =
    { pkgs, ... }:
    {
      environment.systemPackages =
        (with pkgs; [
          xrdb
          xhost
          xrandr
          xprop
          xwininfo
        ])
        ++ packagesFor pkgs;
    };

  flake.modules.homeManager.desktop =
    { pkgs, lib, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
    in
    {
      imports = [
        inputs.ags.homeManagerModules.default
      ];

      programs.ags = lib.mkIf pkgs.stdenv.isLinux {
        enable = true;
        package = inputs.ags.packages.${system}.default;
        extraPackages = [
          pkgs.astal.wireplumber
        ];
      };

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
