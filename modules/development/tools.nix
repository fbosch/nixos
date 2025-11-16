{
  flake.modules.nixos.development = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      git
      cargo
      uv
      gcc
      cmake
      gnumake
      tesseract
      ghostscript
      tectonic
      imagemagick
      lnav
      evemu
      flake-checker
    ];
  };
}
