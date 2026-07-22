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
      configHome = lib.removePrefix config.home.homeDirectory config.xdg.configHome;
      headroomEnvironment = {
        HEADROOM_LOSSLESS = "1";
        HEADROOM_OUTPUT_SHAPER = "1";
        HEADROOM_SAVINGS_PROFILE = "coding";
      };
    in
    {
      home.packages = [ headroomPackage ];

      systemd.user.services.headroom-proxy = lib.mkIf isLinux {
        Unit = {
          Description = "Headroom local proxy";
          After = [ "network-online.target" ];
          X-SwitchMethod = "keep-old";
        };

        Service = {
          Environment = lib.mapAttrsToList (name: value: "${name}=${value}") headroomEnvironment;
          ExecStart = "${headroomPackage}/bin/headroom proxy --host 127.0.0.1 --port 8787";
          Restart = "on-failure";
          RestartSec = 5;
        };

        Install.WantedBy = [ "default.target" ];
      };

      home.activation.restartChangedHeadroomProxy = lib.mkIf isLinux (
        lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
          if [ -n "''${oldGenPath:-}" ]; then
            old_unit="''${oldGenPath}/home-files${configHome}/systemd/user/headroom-proxy.service"
            new_unit="''${newGenPath}/home-files${configHome}/systemd/user/headroom-proxy.service"

            if [ -e "$old_unit" ] && [ -e "$new_unit" ] \
              && ! ${pkgs.diffutils}/bin/cmp -s "$old_unit" "$new_unit"; then
              systemd_status="$(
                env XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
                  ${config.systemd.user.systemctlPath} --user is-system-running 2>&1 || true
              )"

              if [[ "$systemd_status" == running || "$systemd_status" == degraded ]]; then
                run env XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
                  ${config.systemd.user.systemctlPath} --user --no-block restart headroom-proxy.service
              else
                echo "User systemd daemon not running; default.target will start Headroom later."
              fi
            fi
          fi
        ''
      );

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
