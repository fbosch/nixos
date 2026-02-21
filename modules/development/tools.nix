{
  flake.modules.nixos.development =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        git
        cargo
        uv
        gcc
        cmake
        gnumake
        sox
        ffmpeg
        vips
        ghostscript
        tectonic
        librsvg
        imagemagick
        lnav
        evemu
        flake-checker
        statix
        deadnix
        nixpkgs-fmt
      ];
    };

  flake.modules.homeManager.development =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        stylua
        luarocks
        biome
        deno
        docker
        docker-buildx
        bacon
        azure-cli
        units
        ast-grep
        keychain
        openssl
        statix
        deadnix
        nixpkgs-fmt
        posting
        pastel
      ];
    };
}
