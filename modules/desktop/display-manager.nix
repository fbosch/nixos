_: {
  flake.modules.nixos.desktop =
    { pkgs
    , lib
    , config
    , ...
    }:
    let
      nixosConfig = config;

      nixosVersion = "${nixosConfig.system.nixos.release} ${nixosConfig.system.nixos.codeName}";
      issueText = builtins.readFile ../../configs/greetd/issue.txt;

      # Session script for greetd
      sessionScript = builtins.readFile ../../configs/greetd/session-hyprland.sh;
    in
    {
      # Display custom issue banner on login
      environment.etc = {
        "issue".text = ''
          ${issueText}
          ${nixosVersion}
        '';

        "greetd/session-hyprland" = {
          text = sessionScript;
          mode = "0755";
        };
      };

      services.greetd.enable = true;

      programs.regreet = {
        enable = true;
        cageArgs = [
          "-s"
          "-d"
          "-m"
          "last"
        ];
        font = {
          name = "SF Pro Display";
          size = 14;
        };
        theme = {
          name = "MonoThemeDark";
          package = pkgs.emptyDirectory;
        };
        iconTheme = {
          name = "Win11";
          package = pkgs.emptyDirectory;
        };
        cursorTheme = {
          name = "WinSur-white-cursors";
          package = pkgs.emptyDirectory;
        };
        extraCss = builtins.readFile ../../configs/greetd/regreet.css;
        settings = {
          background = {
            path = ../../assets/wallpapers/cube_mono.png;
            fit = "Cover";
          };
          GTK.application_prefer_dark_theme = true;
          greeting_msg = "";
          time_format = "%H:%M";
          commands.reboot = [
            "systemctl"
            "reboot"
          ];
          commands.poweroff = [
            "systemctl"
            "poweroff"
          ];
          default_session = {
            command = "/etc/greetd/session-hyprland";
            name = "Hyprland";
          };
        };
      };

      systemd.services.greetd = {
        wantedBy = [ "graphical.target" ];
      };

      # Enable GNOME Keyring unlock via PAM
      security.pam.services.greetd.enableGnomeKeyring = true;
    };
}
