{
  flake.modules.nixos.applications = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.vicinae ];

    systemd.user.services.vicinae = {
      description = "Vicinae Launcher Daemon";
      documentation = [ "https://docs.vicinae.com" ];
      after = [ "graphical-session.target" ];
      requires = [ "dbus.socket" ];
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.vicinae}/bin/vicinae server --replace";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        Restart = "always";
        RestartSec = 60;
        KillMode = "process";
      };
    };
  };
}
