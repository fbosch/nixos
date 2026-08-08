{ config, ... }:
let
  inherit (config.flake.lib) lazyApp;
  sharedPackages =
    pkgs:
    let
      astGrep =
        if pkgs.stdenv.hostPlatform.isDarwin then
          pkgs.ast-grep.overrideAttrs
            (_: {
              doCheck = false;
            })
        else
          pkgs.ast-grep;
    in
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
    ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux (linuxPackages pkgs)
    ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin (darwinPackages pkgs);

  linuxPackages = pkgs: [
    pkgs.biome
    pkgs.local.fff-mcp
    pkgs.local.lightpanda
  ];

  darwinPackages =
    pkgs:
    let
      azureCli = (pkgs.azure-cli.override { withImmutableConfig = false; }).overrideAttrs (_: {
        doInstallCheck = false;
      });
    in
    [ azureCli ];

  nixosPackages =
    pkgs:
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
    ++ lazyEvemu;
in
{
  flake.modules = {
    nixos.development = { pkgs, ... }: {
      environment.systemPackages = nixosPackages pkgs ++ sharedPackages pkgs;
    };

    darwin.development = { pkgs, ... }: {
      environment.systemPackages = sharedPackages pkgs;
    };

  };
}
