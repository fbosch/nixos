_: {

  flake.modules.homeManager.desktop = { pkgs, inputs, ... }: {
    home.packages = with pkgs; [
      hyprpaper
      hyprprop
      hyprpicker
      grim
      # waycorner
      inputs.hyprland-contrib.packages.${pkgs.stdenv.hostPlatform.system}.grimblast
    ];
  };

  flake.modules.nixos.desktop = { pkgs, meta, inputs, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;

      # Hyprland plugins - upstream now includes API fixes for v0.52.0+
      hyprPluginPkgs = inputs.hyprland-plugins.packages.${system};
      hypr-plugin-dir = pkgs.symlinkJoin {
        name = "hyprland-plugins";
        paths = [ hyprPluginPkgs.hyprexpo hyprPluginPkgs.hyprbars ];
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
            default = [ "hyprland" "gtk" ];
            "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
          };
        };
      };

      programs.hyprland = {
        enable = true;
        withUWSM = true;
        package = inputs.hyprland.packages.${system}.hyprland;
        portalPackage =
          inputs.hyprland.packages.${system}.xdg-desktop-portal-hyprland;
        xwayland.enable = true;
      };

      environment.sessionVariables = {
        EMOJI_FONT = meta.ui.emojiFont;
        NIXOS_OZONE_WL = "1";
        GDK_BACKEND = "wayland,x11";
        QT_QPA_PLATFORM = "wayland";
        WLR_NO_HARDWARE_CURSORS = "1";
        HYPR_PLUGIN_DIR = hypr-plugin-dir;
        GTK_IM_MODULE = "wayland";
        QT_IM_MODULE = "wayland";
        __JAVA_AWT_WM_NONREPARENTING = "1";
        MOZ_ENABLE_WAYLAND = "1";
        XDG_SESSION_TYPE = "wayland";
      };

      environment.systemPackages = [ hyprlockPackage hypridlePackage hyprsunsetPackage ];

      security.pam.services.hyprlock.text = ''
        auth include login
        account include login
      '';

      security.pam.services.hypridle = { };
    };
}
