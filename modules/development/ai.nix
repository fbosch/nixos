{
  flake.modules.homeManager.development =
    { config, pkgs, ... }:
    let
      inherit (pkgs) lib;
      inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
      cfg = config.headroom;

      optionalLocalPackages =
        names:
        lib.pipe names [
          (builtins.filter (name: lib.hasAttr name pkgs.local))
          (builtins.map (name: pkgs.local.${name}))
        ];

      headroomPackage = pkgs.local.headroom or null;
      enableHeadroomService = cfg.service.enable && headroomPackage != null;
    in
    {
      options.headroom.service.enable = lib.mkEnableOption "Headroom local proxy service";

      config = {
        home.packages =
          (with pkgs; [
            codex
            # cursor-cli
            # aichat
            tesseract
          ])
          ++ optionalLocalPackages [
            "headroom"
            "no-mistakes"
            "plannotator"
            "codexbar"
            "rtk"
          ];

        assertions = [
          {
            assertion = !cfg.service.enable || headroomPackage != null;
            message = "headroom.service.enable requires pkgs.local.headroom to be available.";
          }
        ];

        systemd.user.services.headroom-proxy = lib.mkIf (enableHeadroomService && isLinux) {
          Unit = {
            Description = "Headroom local proxy";
            After = [ "network-online.target" ];
          };

          Service = {
            Environment = "HEADROOM_OUTPUT_SHAPER=1";
            ExecStart = "${headroomPackage}/bin/headroom proxy --host 127.0.0.1 --port 8787";
            Restart = "on-failure";
            RestartSec = 5;
          };

          Install.WantedBy = [ "default.target" ];
        };

        launchd.enable = lib.mkIf (enableHeadroomService && isDarwin) true;

        launchd.agents.headroom-proxy = lib.mkIf (enableHeadroomService && isDarwin) {
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
            StandardOutPath = "${config.home.homeDirectory}/Library/Logs/headroom-proxy.out.log";
            StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/headroom-proxy.err.log";
          };
        };
      };
    };
}
