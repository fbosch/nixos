{ config, inputs, ... }:
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
      inherit (config.flake.lib) lazyDesktopApp;

      lazyNwgLook = lazyDesktopApp pkgs {
        pkg = pkgs.nwg-look;
        desktopItem = {
          name = "nwg-look";
          exec = "nwg-look";
          desktopName = "GTK Settings";
          genericName = "Adjust Look and Feel";
          comment = "Customizes GTK3 look and feel settings";
          icon = ../../assets/icons/nwg-look.svg;
          terminal = false;
          notShowIn = [
            "GNOME"
            "KDE"
            "XFCE"
            "MATE"
          ];
          startupNotify = true;
          categories = [
            "GTK"
            "Settings"
            "DesktopSettings"
          ];
          keywords = [
            "windows"
            "preferences"
            "settings"
            "theme"
            "style"
            "appearance"
            "look"
          ];
        };
      };

      lazyNwgDisplays = lazyDesktopApp pkgs {
        pkg = pkgs.nwg-displays;
        desktopItem = {
          name = "nwg-displays";
          exec = "nwg-displays";
          desktopName = "Displays Settings";
          genericName = "Output configuration utility";
          comment = "nwg-shell tool to configure outputs";
          icon = ../../assets/icons/nwg-displays.svg;
          terminal = false;
          categories = [
            "Settings"
            "DesktopSettings"
          ];
        };
      };

      inherit (pkgs.stdenv.hostPlatform) system;
      waybar = pkgs.waybar.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace src/modules/hyprland/workspace.cpp \
            --replace-fail \
            'm_ipc.getSocket1Reply("dispatch workspace " + std::to_string(id()));' \
            'm_ipc.getSocket1Reply("dispatch hl.dsp.focus({ workspace = \"" + std::to_string(id()) + "\" })");'

          substituteInPlace src/modules/sni/item.cpp \
            --replace-fail \
            '} else if (name == "IconName") {' \
            '} else if (name == "IconName" && IconManager::instance().getIconForApp(id).empty()) {' \
            --replace-fail \
            '} else if (name == "IconPixmap") {' \
            '} else if (name == "IconPixmap" && IconManager::instance().getIconForApp(id).empty()) {'
        '';
      });
    in
    {
      imports = [
        inputs.ags.homeManagerModules.default
      ];

      home.packages = lib.optionals pkgs.stdenv.isLinux (
        with pkgs;
        [
          # waycorner
          # rofi
          xwayland
          xwayland-satellite
          setxkbmap
          wev
          lazyNwgLook
          lazyNwgDisplays
          wlr-randr
          wl-clipboard
          xclip
          xsel
          autocutsel
          cliphist
          wl-clip-persist
          wtype
          xdotool
          waybar
          swaynotificationcenter
          libnotify
          swayosd
          gsettings-desktop-schemas
          awww
        ]
      );

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
