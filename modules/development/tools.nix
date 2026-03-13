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
        shellcheck
      ];
    };

  flake.modules.homeManager.development =
    { pkgs, ... }:
    let
      azureCli = (pkgs.azure-cli.override { withImmutableConfig = false; }).overrideAttrs (_: {
        doInstallCheck = false;
      });
      astGrep =
        if pkgs.stdenv.hostPlatform.isDarwin then
          pkgs.ast-grep.overrideAttrs
            (_: {
              doCheck = false;
            })
        else
          pkgs.ast-grep;
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
        astGrep
        keychain
        openssl
        statix
        deadnix
        nixpkgs-fmt
        posting
        pastel
        ripsecrets
        shellcheck
      ];
    };
}
