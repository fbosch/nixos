{ config, ... }:
let
  username = config.flake.meta.user.username;
in
{
  flake.modules.nixos.gaming =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.lact ];

      systemd.packages = [ pkgs.lact ];
      systemd.services.lactd = {
        enable = true;
        # Gaming profile transitions manage the daemon through profilectl.
        wantedBy = lib.mkForce [ ];
      };

      security.polkit.extraConfig = ''
        polkit.addRule(function(action, subject) {
          var verb = action.lookup("verb");
          if (action.id == "org.freedesktop.systemd1.manage-units" &&
              action.lookup("unit") == "lactd.service" &&
              (verb == "start" || verb == "stop") &&
              subject.user == ${builtins.toJSON username}) {
            return polkit.Result.YES;
          }
        });
      '';
    };
}
