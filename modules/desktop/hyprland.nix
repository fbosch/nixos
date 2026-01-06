_: {

  flake.modules.homeManager.desktop =
    { pkgs, inputs, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
      hyprpaperPackages = inputs.hyprpaper.packages.${system};
      hyprpaperPackage = hyprpaperPackages.hyprpaper or hyprpaperPackages.default;
    in
    {
      home.packages = with pkgs; [
        hyprpaperPackage
        hyprprop
        hyprpicker
        grim
        inputs.hyprland-contrib.packages.${pkgs.stdenv.hostPlatform.system}.grimblast
      ];
    };

  flake.modules.nixos.desktop =
    {
      pkgs,
      meta,
      inputs,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;

      # Hyprland plugins - upstream now includes API fixes for v0.52.0+
      hyprPluginPkgs = inputs.hyprland-plugins.packages.${system};
      splitMonitorWorkspacesPkg =
        inputs.split-monitor-workspaces.packages.${system}.split-monitor-workspaces;
      hypr-plugin-dir = pkgs.symlinkJoin {
        name = "hyprland-plugins";
        paths = [
          hyprPluginPkgs.hyprbars
          splitMonitorWorkspacesPkg
        ];
      };

      hyprlockPackages = inputs.hyprlock.packages.${system};
      hyprlockPackage = hyprlockPackages.hyprlock or hyprlockPackages.default;

      hypridlePackages = inputs.hypridle.packages.${system};
      hypridlePackage = hypridlePackages.hypridle or hypridlePackages.default;

      hyprsunsetPackages = inputs.hyprsunset.packages.${system};
      hyprsunsetPackage = hyprsunsetPackages.hyprsunset or hyprsunsetPackages.default;
    in
    {
      xdg.portal = {
        enable = true;
        xdgOpenUsePortal = true;
        extraPortals = [
          inputs.hyprland.packages.${system}.xdg-desktop-portal-hyprland
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
        package = inputs.hyprland.packages.${system}.hyprland;
        portalPackage = inputs.hyprland.packages.${system}.xdg-desktop-portal-hyprland;
        xwayland.enable = true;
      };

      environment.sessionVariables = {
        EMOJI_FONT = meta.ui.emojiFont;
        NIXOS_OZONE_WL = "1";
        GDK_BACKEND = "wayland,x11";
        GDK_DEBUG = "no-portals";
        WLR_NO_HARDWARE_CURSORS = "1";
        HYPR_PLUGIN_DIR = hypr-plugin-dir;
        GTK_IM_MODULE = "wayland";
        QT_QPA_PLATFORM = "wayland;xcb";
        QT_IM_MODULE = "wayland";
        __JAVA_AWT_WM_NONREPARENTING = "1";
        MOZ_ENABLE_WAYLAND = "1";
        XDG_SESSION_TYPE = "wayland";
      };

      environment.systemPackages = [
        hyprlockPackage
        hypridlePackage
        hyprsunsetPackage
      ];

      security.pam.services.hyprlock = {
        enableGnomeKeyring = true;
        text = ''
          auth include login
          account include login
        '';
      };

      security.pam.services.hypridle = { };
    };
}
