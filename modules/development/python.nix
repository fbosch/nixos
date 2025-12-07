{
  flake.modules.homeManager.development = { pkgs, lib, config, ... }:
    let
      pythonProjectDir = "${config.home.homeDirectory}/nixos/configs/python";
      pyprojectPath = ../../configs/python + "/pyproject.toml";

      # Parse pyproject.toml to extract package names
      pyproject = builtins.fromTOML (builtins.readFile pyprojectPath);
      dependencies = pyproject.project.dependencies or [ ];

      # Extract package name before version specifiers (==, >=, <, >, etc.)
      extractPackageName = dep:
        let
          # Remove whitespace and split on common version operators
          cleaned = lib.replaceStrings [ " " ] [ "" ] dep;
          parts =
            lib.splitString "[" cleaned; # Handle extras like package[extra]
          nameWithVersion = builtins.head parts;
          # Split on version operators and take first part
          name = builtins.head (builtins.filter (x: x != "")
            (lib.splitString "="
              (lib.replaceStrings [ ">" "<" "~" "!" ] [ "=" "=" "=" "=" ]
                nameWithVersion)));
        in
        name;

      packageNames = map extractPackageName dependencies;
    in
    {
      home = {
        packages = with pkgs; [
          python3
          python3Packages.evdev
          uv
        ];

        sessionVariables = {
          LD_LIBRARY_PATH = lib.makeLibraryPath (with pkgs; [
            stdenv.cc.cc.lib # libstdc++.so.6
            zlib # libz.so.1
            libGL # libGL.so.1
            libglvnd # Additional OpenGL libraries
          ]);
        };

        activation.installPythonGlobalPackages =
          lib.hm.dag.entryAfter [ "linkGeneration" ] ''
            set -e

            venv_bin="${pythonProjectDir}/.venv/bin"
            local_bin="$HOME/.local/bin"

            echo "Syncing Python tools from uv.lock..."
            ${pkgs.uv}/bin/uv sync --frozen --directory ${pythonProjectDir} || {
              echo "ERROR: Failed to sync Python tools" >&2
              exit 1
            }

            # Symlink all executables to ~/.local/bin
            mkdir -p "$local_bin"
            for tool in ${lib.concatStringsSep " " packageNames}; do
              [ -f "$venv_bin/$tool" ] && ln -sf "$venv_bin/$tool" "$local_bin/$tool"
            done

            echo "✓ Python tools synced to ~/.local/bin"
          '';
      };
    };
}
