{ inputs
, ...
}:
let
  sddmBackground = ../../assets/wallpaper.png;
in
{
  flake.modules.nixos.desktop =
    { config, ... }:
    let
      nixosVersion = config.system.nixos.release;
      linuxKernelVersion = config.boot.kernelPackages.kernel.version;
    in
    {
      imports = [ inputs.silentSDDM.nixosModules.default ];

      programs.silentSDDM = {
        enable = true;
        theme = "default";
        backgrounds = {
          main = sddmBackground;
        };
        settings = {
          General = {
            scale = 1.22;
            enable-animations = true;
          };
          LockScreen = {
            background = "wallpaper.png";
            blur = 7;
          };
          "LockScreen.Clock" = {
            position = "center";
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
            "margin-top" = 12;
          };
          "LockScreen.Message" = {
            "display-icon" = false;
            text = "NixOS ${nixosVersion} | Linux ${linuxKernelVersion}\nPress any key";
            position = "bottom-center";
            "font-family" = "\"SF Pro Text\"";
            "font-size" = 14;
            "font-weight" = 500;
            color = "#B3FFFFFF";
            spacing = 6;
          };
          LoginScreen = {
            background = "wallpaper.png";
            use-background-color = false;
            background-color = "#000000";
            blur = 7;
          };
          "LoginScreen.LoginArea" = {
            position = "center";
            margin = 90;
          };
          "LoginScreen.LoginArea.Avatar" = {
            shape = "circle";
            "active-size" = 80;
            "inactive-size" = 80;
            "inactive-opacity" = 1.0;
          };
          "LoginScreen.LoginArea.PasswordInput" = {
            width = 250;
            height = 48;
            "display-icon" = false;
            border-size = 0;
            "background-color" = "#FFFFFF";
            "border-radius-left" = 22;
            "border-radius-right" = 22;
            "background-opacity" = 0.16;
            "content-color" = "#FFFFFF";
            "font-size" = 20;
            "font-family" = "\"SF Pro Rounded\"";
            "masked-character" = "●";
            "margin-top" = 18;
          };
          "LoginScreen.LoginArea.Username" = {
            "font-family" = "\"SF Pro Text\"";
            "font-size" = 24;
            color = "#B3FFFFFF";
            margin = 14;
          };
          "LoginScreen.LoginArea.LoginButton" = {
            "font-family" = "\"SF Pro Text\"";
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
