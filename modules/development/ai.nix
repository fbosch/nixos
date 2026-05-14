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
          local.no-mistakes
          local.plannotator
        ])
        ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
          pkgs.local.codexbar
          pkgs.local.openpets
          pkgs.local.rtk
        ];
    };
}
