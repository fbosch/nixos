{
  flake.modules.homeManager.development = { pkgs, lib, config, ... }:
    let
      # List of global Python packages to install via uv tool
      # Syntax: "package" or "package==version" for pinned versions
      # To get current versions: uv tool list --show-version-specifiers
      pythonGlobalPackages = [
        "paddleocr"
        "modelscope"
      ];
    in
    {
      home = {
        packages = with pkgs; [
          python3
          uv
        ];

        activation.installPythonGlobalPackages =
          lib.hm.dag.entryAfter [ "linkGeneration" ] ''
            set -e

            mkdir -p "$HOME/.local/share/uv/tools"

            echo "Installing global Python tools via uv..."

            for package in ${
              lib.concatStringsSep " "
              (map lib.escapeShellArg pythonGlobalPackages)
            }; do
              package_name=$(echo "$package" | cut -d'=' -f1 | cut -d'[' -f1)

              if ${pkgs.uv}/bin/uv tool list 2>/dev/null | grep -q "^$package_name "; then
                echo "✓ $package_name already installed"
              else
                echo "Installing $package..."
                if ! $DRY_RUN_CMD ${pkgs.uv}/bin/uv tool install "$package" 2>&1; then
                  echo "ERROR: Failed to install $package" >&2
                else
                  echo "✓ Installed $package"
                fi
              fi
            done

            echo ""
            echo "Python tools available in ~/.local/bin"
          '';
      };
    };
}
