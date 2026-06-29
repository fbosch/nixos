{
  flake.modules.homeManager.development =
    { pkgs, ... }:
    let
      headroom = pkgs.writeShellApplication {
        name = "headroom";
        runtimeInputs = [ pkgs.uv ];
        text = ''
          exec uvx --from 'headroom-ai[mcp]==0.27.0' headroom "$@"
        '';
      };
    in
    {
      home.packages =
        (with pkgs; [
          codex
          headroom
          # cursor-cli
          # aichat
          tesseract
        ])
        ++ pkgs.lib.optional (pkgs.local ? no-mistakes) pkgs.local.no-mistakes
        ++ pkgs.lib.optional (pkgs.local ? plannotator) pkgs.local.plannotator
        ++ pkgs.lib.optional (pkgs.local ? codexbar) pkgs.local.codexbar
        ++ pkgs.lib.optional (pkgs.local ? rtk) pkgs.local.rtk;
    };
}
