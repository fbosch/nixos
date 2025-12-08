_: {

  flake.modules.homeManager.desktop = { pkgs, inputs, ... }: {
    home.packages = with pkgs; [
      hyprpaper
      hyprprop
      hyprpicker
      grim
      inputs.hyprland-contrib.packages.${pkgs.stdenv.hostPlatform.system}.grimblast
    ];
  };

  flake.modules.nixos.desktop = { pkgs, meta, inputs, lib, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
      hyprlandPkg = inputs.hyprland.packages.${system}.hyprland;

      # Fix the hyprland.pc file to have proper pkg-config syntax
      # The issue is "xkbcommon >=1.11.0" should be "xkbcommon >= 1.11.0" (space before >=)
      hyprlandPkgFixed = hyprlandPkg.dev.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          # Fix pkg-config file syntax - add space before >= operators
          sed -i 's/xkbcommon >=\([0-9]\)/xkbcommon >= \1/g' $out/share/pkgconfig/hyprland.pc
        '';
      });

      # Build plugins from hyprland-plugins flake with proper Hyprland dependency
      hyprPluginPkgs = inputs.hyprland-plugins.packages.${system};

      # Override each plugin to use the fixed Hyprland version in buildInputs
      mkPlugin = plugin:
        plugin.overrideAttrs (old: {
          buildInputs =
            # Filter out any hyprland package and replace with our fixed version
            (lib.filter
              (input:
                !(lib.hasInfix "hyprland" (input.pname or input.name or "")))
              old.buildInputs) ++ [ hyprlandPkgFixed ];
        });

      hypr-plugin-dir = pkgs.symlinkJoin {
        name = "hyprland-plugins";
        paths = [
          (mkPlugin hyprPluginPkgs.hyprexpo)
          (mkPlugin hyprPluginPkgs.hyprbars)
        ];
      };

      hyprlockPackages = inputs.hyprlock.packages.${system};
      hyprlockPackage = hyprlockPackages.hyprlock or hyprlockPackages.default;
    in
    {
      xdg.portal = {
        enable = true;
        xdgOpenUsePortal = false;
        extraPortals = [
          inputs.hyprland.packages.${system}.xdg-desktop-portal-hyprland
          pkgs.xdg-desktop-portal-gtk
        ];
        config = {
          common = { default = [ "gtk" ]; };
          hyprland = { default = [ "hyprland" "gtk" ]; };
        };
      };

      programs.hyprland = {
        enable = true;
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

      environment.systemPackages = [ hyprlockPackage ];

      security.pam.services.hyprlock.text = ''
        auth include login
        account include login
      '';
    };
}
