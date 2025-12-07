_: {
  # OCR tools for Hyprland screenshot workflow
  # 
  # Provides PaddleOCR and dependencies via a uv2nix-built Python virtual environment.
  # The ocr-tools workspace is defined in modules/development/workspaces/ocr-tools/
  # and built via the Python workspace helper in modules/flake-parts/python-workspaces.nix
  #
  # The virtual environment includes:
  # - PaddleOCR for text extraction from images
  # - All required dependencies (opencv, paddlepaddle, etc.)
  #
  # Usage in dotfiles scripts (e.g., ~/.config/hypr/scripts/paddleocr_extract.py):
  #   from paddleocr import PaddleOCR
  #   ocr = PaddleOCR(use_angle_cls=True, lang="en", show_log=False)
  #
  # The system Python can import from the venv via PYTHONPATH

  flake.modules.homeManager.desktop = { pkgs, ... }: {
    home.packages = [
      pkgs.tesseract # Fallback OCR engine
    ];

    # Make PaddleOCR available to system Python via PYTHONPATH
    home.sessionVariables = {
      PYTHONPATH = "${pkgs.local.ocr-tools}/${pkgs.python312.sitePackages}";
    };
  };
}
