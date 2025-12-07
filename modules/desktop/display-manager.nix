_: {
  flake.modules.nixos.desktop = { pkgs, lib, config, ... }:
    let
      tuigreetTheme = builtins.readFile ../../configs/tuigreet/theme.txt;
      nixosVersion = "${config.system.nixos.release} (${config.system.nixos.codeName})";
      issueText = builtins.readFile ../../configs/tuigreet/issue.txt;
    in
    {
      environment.etc."issue".text = ''
        ${issueText}
        ${nixosVersion}
      '';

      environment.etc."tuigreet/session" = {
        text = builtins.readFile ../../configs/tuigreet/start-hyprland.sh;
        mode = "0755";
      };

      services.greetd = {
        enable = true;
        settings = {
          default_session = {
            command =
              "${pkgs.tuigreet}/bin/tuigreet --time --remember --asterisks --issue --greet-align center --theme ${
                lib.escapeShellArg (lib.removeSuffix "\n" tuigreetTheme)
              } --sessions '' --cmd /etc/tuigreet/session";
            user = "greeter";
          };
        };
      };

      systemd.services.greetd = { wantedBy = [ "graphical.target" ]; };

      security.pam.services.greetd.enableGnomeKeyring = true;
    };
}
