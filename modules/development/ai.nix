{
  flake.modules.homeManager.development =
    { pkgs, ... }:
    {
      home.packages =
        (with pkgs; [
          codex
          cursor-cli
          aichat
          tesseract
          claude-code
        ])
        ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
          pkgs.local.codexbar
        ];
    };
}
