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
      # Fabric 3.2.3 requires Invoke <3. Remove this pin when Fabric supports Invoke 3.
      # Keep the same Invoke version for Fabric and Paramiko within Azure CLI's Python scope.
      # https://github.com/fabric/fabric/issues/2376
      azureCliPkgs = pkgs.extend (
        _: prev: {
          pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
            (_: pythonPrev: {
              invoke = pythonPrev.invoke.overridePythonAttrs (old: rec {
                version = "2.2.1";
                src = prev.fetchPypi {
                  inherit (old) pname;
                  inherit version;
                  hash = "sha256-UVv0m0pIkyt5sCRZA0jaIvOcSULf+ZGtH7i4uuob5wc=";
                };
              });
            })
          ];
        }
      );
      azureCli = (azureCliPkgs.azure-cli.override { withImmutableConfig = false; }).overrideAttrs (_: {
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
