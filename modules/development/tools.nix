{
  flake.modules.homeManager.development.tools = { pkgs, ... }: {
    home.packages = with pkgs; [
      codex
      tesseract
    ];
  };
}
