let
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
          posting
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

      environment.systemPackages = with pkgs; [
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
        evemu
      ];
    };

    darwin.development = {
      imports = [ sharedSystemPackages ];
    };

  };
}
