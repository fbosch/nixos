{
  flake.modules.homeManager."development/services/pxpipe" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
      pxpipePackage = pkgs.local.pxpipe;
    in
    {
      home.packages = [ pxpipePackage ];

      systemd.user.services.pxpipe = lib.mkIf isLinux {
        Unit = {
          Description = "pxpipe local proxy";
          After = [ "network-online.target" ];
        };

        Service = {
          Environment = [ "PORT=47821" ];
          ExecStart = "${pxpipePackage}/bin/pxpipe";
          Restart = "on-failure";
          RestartSec = 5;
        };

        Install.WantedBy = [ "default.target" ];
      };

      launchd.enable = lib.mkIf isDarwin true;

      launchd.agents.pxpipe = lib.mkIf isDarwin {
        enable = true;
        config = {
          ProgramArguments = [ "${pxpipePackage}/bin/pxpipe" ];
          EnvironmentVariables.PORT = "47821";
          RunAtLoad = true;
          KeepAlive = true;
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/pxpipe.out.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/pxpipe.err.log";
        };
      };
    };
}
