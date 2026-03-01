{
  flake.modules.nixos.development =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        git
        just
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
    let
      azureCli = (pkgs.azure-cli.override { withImmutableConfig = false; }).overrideAttrs (_: {
        doInstallCheck = false;
      });
    in
    {
      home.packages = with pkgs; [
        stylua
        luarocks
        biome
        deno
        docker
        docker-buildx
        bacon
        azureCli
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
