{ inputs, ... }:
{

  flake.modules.homeManager.desktop = { pkgs, ... }: {
    home.packages = with pkgs; [
      hyprpaper
      hyprprop
      hyprpicker
      inputs.hyprland-contrib.packages.${pkgs.system}.grimblast
    ];
  };

  flake.modules.nixos.desktop = { pkgs, ... }:
    let
      hyprPluginPkgs = inputs.hyprland-plugins.packages.${pkgs.system};
      hypr-plugin-dir = pkgs.symlinkJoin {
        name = "hyprland-plugins";
        paths = with hyprPluginPkgs; [
          hyprexpo
          hyprbars
          inputs.hyprspace.packages.${pkgs.system}.Hyprspace
        ];
      };
      hyprlockPackages =
        inputs.hyprlock.packages.${pkgs.stdenv.hostPlatform.system};
      hyprlockPackage = hyprlockPackages.hyprlock or hyprlockPackages.default;
    in {
      xdg.portal = {
        enable = true;
        xdgOpenUsePortal = true;
        extraPortals = [
          inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland
          pkgs.xdg-desktop-portal-gtk
          pkgs.xdg-desktop-portal-wlr
        ];
        config.common.default = "gtk";
      };

      programs.hyprland = {
        enable = true;
        withUWSM = true;
        package =
          inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
        portalPackage =
          inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
        xwayland.enable = true;
      };

      environment.sessionVariables = {
        EMOJI_FONT = "Apple Color Emoji";
        NIXOS_OZONE_WL = "1";
        GDK_BACKEND = "wayland,x11";
        QT_QPA_PLATFORM = "wayland";
        GSK_RENDERER = "cairo";
        WLR_NO_HARDWARE_CURSORS = "1";
        WLR_RENDERER_ALLOW_SOFTWARE = "1";
        HYPR_PLUGIN_DIR = hypr-plugin-dir;
        GTK_IM_MODULE = "wayland";
        QT_IM_MODULE = "wayland";
        __JAVA_AWT_WM_NONREPARENTING = "1";
        MOZ_ENABLE_WAYLAND = "1";
        XDG_SESSION_TYPE = "wayland";
      };

      environment.systemPackages = [ hyprlockPackage ];

      security.pam.services.hyprlock.text = ''
        auth include login
        account include login
      '';
    };
}
