{ config, ... }:
let
  inherit (config.flake.lib) lazyApp;
in
{
  flake.modules.nixos.development =
    { pkgs, ... }:
    let
      lazyEvemu =
        map
          (
            exe:
            lazyApp pkgs {
              inherit exe;
              pkg = pkgs.evemu;
            }
          )
          [
            "evemu-describe"
            "evemu-device"
            "evemu-event"
            "evemu-play"
            "evemu-record"
          ];
    in
    {
      environment.systemPackages =
        (with pkgs; [
          git
          just
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
          flake-checker
          statix
          deadnix
          nixpkgs-fmt
          shellcheck
          luajitPackages.luacheck
        ])
        ++ lazyEvemu;
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
      home.packages =
        (with pkgs; [
          tree-sitter
          stylua
          luarocks
          biome
          deno
          docker
          docker-buildx
          docker-compose-language-service
          bacon
          sqlite
          units
          astGrep
          keychain
          openssl
          devenv
          statix
          deadnix
          nixpkgs-fmt
          (lazyApp pkgs posting)
          pastel
          ripsecrets
          shellcheck
          luajitPackages.luacheck
        ])
        ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
          pkgs.local.lightpanda
          pkgs.local.limux
        ]
        ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
          # work only tooling
          azureCli
        ];
    };
}
