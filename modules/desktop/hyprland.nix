{ inputs, ... }:
{
  flake.modules = {
    homeManager.desktop =
      { pkgs
      , lib
      , ...
      }:
      let
        inherit (pkgs.stdenv.hostPlatform) system;
        luaWithSocket = pkgs.lua5_2.withPackages (ps: [ ps.luasocket ]);
      in
      {
        home.packages = lib.optionals pkgs.stdenv.isLinux [
          inputs.hyprpaper.packages.${system}.hyprpaper
          pkgs.hyprprop
          pkgs.hyprpicker
          pkgs.grim
          luaWithSocket
          inputs.hyprland-contrib.packages.${system}.grimblast
        ];
      };

    nixos = {
      desktop =
        { pkgs
        , ...
        }:
        let
          inherit (pkgs.stdenv.hostPlatform) system;

          hyprlandPackage = inputs.hyprland.packages.${system}.hyprland;
          hyprfocusPlugin = inputs.hyprland-plugins.packages.${system}.hyprfocus;
          xdgDesktopPortalHyprlandPackage =
            inputs.hyprland.packages.${system}.xdg-desktop-portal-hyprland.override
              {
                hyprland = hyprlandPackage;
              };
        in
        {
          xdg.portal = {
            enable = true;
            xdgOpenUsePortal = true;
            extraPortals = [
              xdgDesktopPortalHyprlandPackage
              pkgs.xdg-desktop-portal-gtk
            ];
            config = {
              hyprland = {
                default = [
                  "hyprland"
                  "gtk"
                ];
                "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
              };
            };
          };

          programs.hyprland = {
            enable = true;
            withUWSM = true;
            package = hyprlandPackage;
            portalPackage = xdgDesktopPortalHyprlandPackage;
            xwayland.enable = true;
          };

          systemd.tmpfiles.rules = [
            "d /usr/share 0755 root root - -"
            "d /usr/share/hypr 0755 root root - -"
            "L+ /usr/share/hypr/stubs - - - - ${hyprlandPackage}/share/hypr/stubs"
          ];

          environment.sessionVariables = {
            EMOJI_FONT = "Apple Color Emoji";
            NIXOS_OZONE_WL = "1";
            GDK_BACKEND = "wayland,x11";
            GSK_RENDERER = "ngl";
            ADW_DEBUG_COLOR_SCHEME = "prefer-dark";
            WLR_NO_HARDWARE_CURSORS = "1";
            __GL_GSYNC_ALLOWED = "1";
            __GL_VRR_ALLOWED = "1";
            QT_QPA_PLATFORM = "wayland;xcb";
            QT_IM_MODULE = "wayland";
            __JAVA_AWT_WM_NONREPARENTING = "1";
            MOZ_ENABLE_WAYLAND = "1";
            XDG_SESSION_TYPE = "wayland";
            HYPRFOCUS_PLUGIN = "${hyprfocusPlugin}/lib/libhyprfocus.so";
          };

          environment.systemPackages = [
            inputs.hyprlock.packages.${system}.hyprlock
            inputs.hypridle.packages.${system}.hypridle
            inputs.hyprsunset.packages.${system}.hyprsunset
            pkgs.hyprshutdown
          ];

          security.pam.services = {
            hyprland.enableGnomeKeyring = true;
            hyprlock = {
              enableGnomeKeyring = true;
            };
            hypridle = { };
          };
        };

      "desktop/hyprwhspr-rs" =
        { pkgs, ... }:
        {
          services.hyprwhspr-rs.enable = true;
          environment.systemPackages = [ pkgs.hyprwhspr-rs ];
        };
    };
  };
}
