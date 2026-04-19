{ inputs, ... }:
let
  sddmBackground = ../../assets/wallpaper.png;
in
{
  flake.modules.nixos.desktop = {
    imports = [ inputs.silentSDDM.nixosModules.default ];

    programs.silentSDDM = {
      enable = true;
      theme = "default";
      backgrounds = {
        main = sddmBackground;
      };
      settings = {
        General = {
          scale = 1.0;
          enable-animations = true;
        };
        LockScreen = {
          background = "wallpaper.png";
          blur = 7;
        };
        "LockScreen.Clock" = {
          "font-family" = "\"SF Pro Rounded\"";
          format = "HH:mm";
          "font-size" = 140;
          "font-weight" = 700;
          color = "#E6FFFFFF";
        };
        "LockScreen.Date" = {
          "font-family" = "\"SF Pro Rounded\"";
          format = "dddd, dd MMMM";
          locale = "en_US";
          "font-size" = 23;
          "font-weight" = 500;
          color = "#B3FFFFFF";
          "margin-top" = -30;
        };
        LoginScreen = {
          background = "wallpaper.png";
          use-background-color = false;
          background-color = "#000000";
          blur = 7;
        };
        "LoginScreen.LoginArea" = {
          position = "center";
          margin = -1;
        };
        "LoginScreen.LoginArea.Avatar" = {
          shape = "circle";
          "active-size" = 80;
          "inactive-size" = 80;
          "inactive-opacity" = 1.0;
        };
        "LoginScreen.LoginArea.PasswordInput" = {
          width = 230;
          height = 43;
          border-size = 0;
          "border-radius-left" = 22;
          "border-radius-right" = 22;
          "background-opacity" = 0.12;
          "content-color" = "#BFFFFFFF";
          "font-size" = 18;
          "font-family" = "\"SF Pro Rounded\"";
        };
        "LoginScreen.LoginArea.Username" = {
          "font-family" = "\"SF Pro Rounded\"";
          "font-size" = 23;
          color = "#B3FFFFFF";
        };
        "LoginScreen.LoginArea.LoginButton" = {
          "font-family" = "\"SF Pro Rounded\"";
          "font-size" = 18;
        };
      };
    };

    services.displayManager = {
      ly.enable = false;
      sddm = {
        wayland = {
          enable = true;
          compositor = "weston";
        };
        settings = {
          Theme = {

            EnableAvatars = true;
            FacesDir = "/etc/sddm/faces";
          };
        };
      };
      defaultSession = "hyprland-uwsm";
    };

    systemd.services.display-manager.environment = {
      XCURSOR_THEME = "WinSur-white-cursors";
      XCURSOR_SIZE = "28";
      XCURSOR_PATH = "/run/current-system/sw/share/icons";
    };
  };
}
