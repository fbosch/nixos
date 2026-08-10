{ config, ... }:
let
  inherit (config.flake.lib) lazyApp;
  sharedSystemPackages =
    { pkgs, ... }:
    let
      astGrep =
        if pkgs.stdenv.hostPlatform.isDarwin then
          pkgs.ast-grep.overrideAttrs
            (_: {
              doCheck = false;
            })
        else
          pkgs.ast-grep;
      azureCli = (pkgs.azure-cli.override { withImmutableConfig = false; }).overrideAttrs (_: {
        doInstallCheck = false;
      });
    in
    {
      environment.systemPackages =
        (with pkgs; [
          tree-sitter
          stylua
          luarocks
          deno
          bacon
          sqlite
          units
          astGrep
          keychain
          openssl
          devenv
          (lazyApp pkgs posting)
          pastel
          ripsecrets
          luajitPackages.luacheck
        ])
        ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
          pkgs.biome
          pkgs.local.fff-mcp
          pkgs.local.lightpanda
        ]
        ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ azureCli ];
    };
in
{
  flake.modules = {
    nixos.development = { pkgs, ... }: {
      imports = [ sharedSystemPackages ];

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
        ])
        ++
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
    };

    darwin.development = {
      imports = [ sharedSystemPackages ];
    };

  };
}
