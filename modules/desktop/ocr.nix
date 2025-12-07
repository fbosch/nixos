{
  # OCR tools for Hyprland screenshot workflow
  # 
  # TEMPORARILY DISABLED: Requires fixing GitHub token in SOPS
  # 
  # To enable:
  # 1. Update GitHub token in secrets/secrets.yaml with a valid token
  # 2. Rebuild system to activate the token
  # 3. Uncomment the uv2nix package build below
  # 4. The package will build Python OCR tools with proper build dependencies
  #
  # This uses uv2nix to build Python packages through Nix for full reproducibility.
  # The uv.lock file at modules/development/workspaces/ocr-tools/uv.lock ensures
  # deterministic builds across all machines.

  # flake.modules.homeManager.desktop = { pkgs, ... }: {
  #   home.packages = [
  #     config.flake.packages.${pkgs.stdenv.hostPlatform.system}.ocr-tools
  #   ];
  # };
}
