_: {
  # OCR tools for Hyprland screenshot workflow
  # 
  # Provides PaddleOCR via a Python wrapper script that uses the ocr-tools venv.
  # The ocr-tools workspace is defined in modules/development/workspaces/ocr-tools/
  # and built via the Python workspace helper in modules/flake-parts/python-workspaces.nix
  #
  # The virtual environment includes:
  # - PaddleOCR for text extraction from images
  # - All required dependencies (opencv, paddlepaddle, etc.)
  #
  # Usage in dotfiles scripts (e.g., ~/.config/hypr/scripts/paddleocr_extract.py):
  #   Update shebang to: #!/usr/bin/env ocr-python
  #   Then use: from paddleocr import PaddleOCR

  flake.modules.homeManager.desktop = { pkgs, ... }:
    let
      # Wrapper script that runs Python with access to the ocr-tools venv
      ocr-python = pkgs.writeShellScriptBin "ocr-python" ''
        exec ${pkgs.local.ocr-tools}/bin/python "$@"
      '';
    in
    {
      home.packages = [
        ocr-python # Python wrapper with PaddleOCR available
        pkgs.tesseract # Fallback OCR engine
      ];
    };
}
