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
        ])
        ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
          pkgs.local.codexbar
          pkgs.local.rtk
        ];
    };
}
