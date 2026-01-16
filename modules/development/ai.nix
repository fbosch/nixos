{
  flake.modules.homeManager.development = { pkgs, ... }: {
    home.packages = with pkgs; [ codex cursor-cli aichat tesseract claude-code ];
  };
}
