{
  flake.modules.homeManager.development =
    { pkgs, ... }:
    {
      home.packages =
        (with pkgs; [
          codex
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
