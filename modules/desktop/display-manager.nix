_: {
  flake.modules.nixos.desktop =
    { pkgs
    , lib
    , config
    , ...
    }:
    let
      nixosConfig = config;

      # TUIGreet configuration
      tuigreetTheme = builtins.readFile ../../configs/greetd/theme.txt;
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

      # Greetd with TUIGreet
      services.greetd = {
        enable = true;
        settings = {
          default_session = {
            command = ''
              ${pkgs.tuigreet}/bin/tuigreet --time --remember --asterisks --issue --greet-align center --theme ${lib.escapeShellArg (lib.removeSuffix "\n" tuigreetTheme)} --sessions "" --cmd /etc/greetd/session-hyprland
            '';
            user = "greeter";
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
