{ inputs, ... }:
{
  flake.modules.nixos.desktop = {
    imports = [ inputs.silentSDDM.nixosModules.default ];

    programs.silentSDDM = {
      enable = true;
      theme = "default";
      settings = {
        General = {
          scale = 1.0;
          enable-animations = true;
        };
        LoginScreen = {
          use-background-color = false;
          background-color = "#000000";
          blur = 0;
          brightness = 0.0;
          saturation = 0.0;
        };
        "LoginScreen.LoginArea" = {
          position = "center";
          margin = -1;
        };
        "LoginScreen.LoginArea.PasswordInput" = {
          width = 200;
          height = 30;
          border-size = 0;
          "font-family" = "SF Pro Rounded";
        };
        "LoginScreen.LoginArea.Username" = {
          "font-family" = "SF Pro Rounded";
        };
        "LoginScreen.LoginArea.LoginButton" = {
          "font-family" = "SF Pro Rounded";
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
  };
}
