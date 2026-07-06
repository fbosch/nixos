{
  flake.modules.homeManager.development =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;

      optionalLocalPackages =
        names:
        lib.pipe names [
          (builtins.filter (name: lib.hasAttr name pkgs.local))
          (builtins.map (name: pkgs.local.${name}))
        ];

      headroomPackage = pkgs.local.headroom or null;
    in
    {
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

      systemd.user.services.headroom-proxy = lib.mkIf (headroomPackage != null) {
        Unit = {
          Description = "Headroom local proxy";
          After = [ "network-online.target" ];
        };

        Service = {
          ExecStart = "${headroomPackage}/bin/headroom proxy --host 127.0.0.1 --port 8787";
          Restart = "on-failure";
          RestartSec = 5;
        };

        Install.WantedBy = [ "default.target" ];
      };
    };
}
