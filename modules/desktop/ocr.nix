_: {
  flake.modules.homeManager.desktop = { pkgs, ... }: {
    home.packages = [
      pkgs.local.ocr-tools # Python venv with PaddleOCR
      pkgs.tesseract # Fallback OCR engine
    ];
  };
}
