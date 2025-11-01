{
  flake.modules.nixos.development = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      git
      cargo
      gcc
      cmake
      gnumake
      tesseract
    ];
  };
}
