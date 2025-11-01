{
  flake.modules.nixos.development = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      fnm
      git
      cargo
      gcc
      cmake
      gnumake
      tesseract
    ];
  };
}
