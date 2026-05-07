{ inputs
, ...
}:
let
  sddmBackground = ../../assets/wallpapers/glaze_2.png;
in
{
  flake.modules.nixos.desktop =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      nixosVersion = config.system.nixos.release;
      linuxKernelVersion = config.boot.kernelPackages.kernel.version;
      fishSession =
        (pkgs.writeTextDir "share/wayland-sessions/fish.desktop" ''
          [Desktop Entry]
          Name=Fish
          Comment=Fish shell session
          Exec=${lib.getExe pkgs.cage} -s -- ${lib.getExe pkgs.foot} ${lib.getExe pkgs.fish}
          Type=Application
          DesktopNames=fish
        '').overrideAttrs
          (_: {
            passthru.providedSessions = [ "fish" ];
          });
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
            scale = 1.0;
            enable-animations = true;
          };
          LockScreen = {
            background = "wallpaper.png";
            blur = 7;
            "padding-top" = 150;
          };
          "LockScreen.Clock" = {
            position = "top-center";
            "font-family" = "\"SF Pro Rounded\"";
            format = "HH:mm";
            "font-size" = 120;
            "font-weight" = 700;
            color = "#E6FFFFFF";
          };
          "LockScreen.Date" = {
            "font-family" = "\"SF Pro Rounded\"";
            format = "dddd, dd MMMM";
            locale = "en_US";
            "font-size" = 18;
            "font-weight" = 500;
            color = "#B3FFFFFF";
            "margin-top" = 6;
          };
          "LockScreen.Message" = {
            text = "NixOS ${nixosVersion} | Linux ${linuxKernelVersion}\nPress any key";
            position = "bottom-center";
            "font-family" = "\"SF Pro Text\"";
            color = "#B3FFFFFF";
            spacing = 6;
          };
          LoginScreen = {
            background = "wallpaper.png";
            use-background-color = false;
            background-color = "#000000";
            blur = 7;
          };
          "LoginScreen.LoginArea.Avatar" = {
            shape = "circle";
            "active-size" = 120;
            "inactive-size" = 120;
            "inactive-opacity" = 1.0;
          };
          "LoginScreen.LoginArea.PasswordInput" = {
            border-size = 0;
            "background-color" = "#FFFFFF";
            "border-radius-left" = 18;
            "border-radius-right" = 18;
            "background-opacity" = 0.14;
            "content-color" = "#FFFFFF";
            "font-size" = 12;
            "font-family" = "\"SF Pro Rounded\"";
            "masked-character" = "●";
            "margin-top" = 10;
          };
          "LoginScreen.LoginArea.Username" = {
            "font-family" = "\"SF Pro Text\"";
            color = "#FFFFFF";
          };
          "LoginScreen.LoginArea.LoginButton" = {
            "font-family" = "\"SF Pro Text\"";
            "hide-if-not-needed" = true;
          };
        };
      };

      services.displayManager = {
        ly.enable = false;
        sessionPackages = [ fishSession ];
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

      security.pam.services.sddm.rules = {
        auth.login.modulePath = lib.mkForce "/etc/pam.d/login";
        account.login.modulePath = lib.mkForce "/etc/pam.d/login";
        password.login.modulePath = lib.mkForce "/etc/pam.d/login";
        session.login.modulePath = lib.mkForce "/etc/pam.d/login";
      };

      security.pam.services.sddm-autologin.rules = {
        account.sddm.modulePath = lib.mkForce "/etc/pam.d/sddm";
        password.sddm.modulePath = lib.mkForce "/etc/pam.d/sddm";
        session.sddm.modulePath = lib.mkForce "/etc/pam.d/sddm";
      };

      systemd.services.display-manager.environment = {
        XCURSOR_THEME = "WinSur-white-cursors";
        XCURSOR_SIZE = "28";
        XCURSOR_PATH = "/run/current-system/sw/share/icons";
      };
    };
}
