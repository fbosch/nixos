{
  flake.modules.homeManager.development = { pkgs, ... }: {
    home.packages = with pkgs; [
      codex
      tesseract
    ];
  };
}
