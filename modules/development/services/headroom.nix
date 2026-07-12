{
  flake.modules.homeManager."development/services/headroom" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
      headroomPackage = pkgs.local.headroom;
      headroomEnvironment = {
        HEADROOM_ACCURACY_GUARD = "strict";
        HEADROOM_COMPRESS_SYSTEM_MESSAGES = "0";
        HEADROOM_COMPRESS_USER_MESSAGES = "0";
        HEADROOM_FORCE_KOMPRESS = "0";
        HEADROOM_LOSSLESS = "1";
        HEADROOM_MAX_ITEMS = "15";
        HEADROOM_MIN_TOKENS = "25";
        HEADROOM_MODE = "token";
        HEADROOM_OUTPUT_SHAPER = "1";
        HEADROOM_PROTECT_ANALYSIS_CONTEXT = "1";
        HEADROOM_PROTECT_RECENT = "2";
        HEADROOM_SAVINGS_PROFILE = "coding";
        HEADROOM_SAVINGS_TARGET = "0.50";
        HEADROOM_SMART_CRUSHER_COMPACTION = "1";
      };
    in
    {
      home.packages = [ headroomPackage ];

      systemd.user.services.headroom-proxy = lib.mkIf isLinux {
        Unit = {
          Description = "Headroom local proxy";
          After = [ "network-online.target" ];
        };

        Service = {
          Environment = lib.mapAttrsToList (name: value: "${name}=${value}") headroomEnvironment;
          ExecStart = "${headroomPackage}/bin/headroom proxy --host 127.0.0.1 --port 8787";
          Restart = "on-failure";
          RestartSec = 5;
        };

        Install.WantedBy = [ "default.target" ];
      };

      launchd.enable = lib.mkIf isDarwin true;

      launchd.agents.headroom-proxy = lib.mkIf isDarwin {
        enable = true;
        config = {
          ProgramArguments = [
            "${headroomPackage}/bin/headroom"
            "proxy"
            "--host"
            "127.0.0.1"
            "--port"
            "8787"
          ];
          RunAtLoad = true;
          KeepAlive = true;
          EnvironmentVariables = headroomEnvironment;
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/headroom-proxy.out.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/headroom-proxy.err.log";
        };
      };
    };
}
