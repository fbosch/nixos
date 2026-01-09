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
        # Nix linting and code quality tools
        statix
        deadnix
        nixpkgs-fmt
      ];
    };

  flake.modules.homeManager.development =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        # Additional development utilities
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
      ];
    };
}
