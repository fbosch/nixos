{ inputs, ... }:
{
  flake.modules.homeManager.desktop =
    { pkgs, lib, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
      agsPackages = inputs.ags.packages.${system};
      agsBundleRuntime = pkgs.stdenvNoCC.mkDerivation {
        pname = "ags-bundle-runtime";
        version = "1";
        dontUnpack = true;
        nativeBuildInputs = [
          pkgs.gobject-introspection
          pkgs.wrapGAppsHook3
        ];
        buildInputs = [
          pkgs.evolution-data-server
          pkgs.gjs
          pkgs.glib
          pkgs.astal.wireplumber
          agsPackages.astal4
          agsPackages.io
        ];
        installPhase = ''
          mkdir -p "$out/bin"
          cat > "$out/bin/ags-bundle-runtime" <<'EOF'
          #!${pkgs.bash}/bin/bash
          set -euo pipefail

          if [[ "$#" -ne 1 ]]; then
            printf 'Usage: ags-bundle-runtime <bundle>\n' >&2
            exit 2
          fi

          exec "$1"
          EOF
          chmod +x "$out/bin/ags-bundle-runtime"
        '';
      };
    in
    {
      imports = [
        inputs.ags.homeManagerModules.default
      ];

      programs.ags = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        enable = true;
        package = inputs.ags.packages.${system}.default;
        extraPackages = [
          pkgs.astal.wireplumber
        ];
      };

      home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
        agsBundleRuntime
      ];
    };
}
