_: {
  flake.modules.nixos.desktop = { pkgs, lib, meta, ... }:
    let
      startHyprlandScript = pkgs.writeShellScriptBin "start-hyprland"
        (builtins.readFile ../../configs/tuigreet/start-hyprland.sh);
      tuigreetTheme = builtins.readFile ../../configs/tuigreet/theme.txt;
    in
    {
      environment.etc."issue".text = builtins.readFile ../../configs/tuigreet/issue.txt;

      services.greetd = {
        enable = true;
        settings = {
          default_session = {
            command =
              "${pkgs.tuigreet}/bin/tuigreet --time --remember --asterisks --issue --greet-align center --theme ${
                lib.escapeShellArg (lib.removeSuffix "\n" tuigreetTheme)
              } --cmd ${startHyprlandScript}/bin/start-hyprland";
            user = "greeter";
          };
        };
      };

      systemd.services.greetd = { wantedBy = [ "graphical.target" ]; };

      security.pam.services.greetd.enableGnomeKeyring = true;
    };
}
