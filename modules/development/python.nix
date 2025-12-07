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
          # System libraries required by PaddleOCR (opencv-python)
          libGL
          glib
          zlib
          stdenv.cc.cc.lib # Provides libstdc++.so.6
        ];

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

            # Create a wrapper for venv Python with proper library paths
            cat > "$local_bin/python-venv" <<WRAPPER_EOF
            #!/usr/bin/env bash
            # Auto-generated wrapper for Python venv with library paths
            LIBS=""
            # Add glib, libGL, zlib, and stdenv (libstdc++) from home-manager packages
            LIBS="${pkgs.glib.out}/lib:\$LIBS"
            LIBS="${pkgs.libGL}/lib:\$LIBS"
            LIBS="${pkgs.zlib}/lib:\$LIBS"
            LIBS="${pkgs.stdenv.cc.cc.lib}/lib:\$LIBS"
            # Add standard profile paths
            [[ -d "\$HOME/.nix-profile/lib" ]] && LIBS="\$HOME/.nix-profile/lib:\$LIBS"
            [[ -d "/etc/profiles/per-user/\$USER/lib" ]] && LIBS="/etc/profiles/per-user/\$USER/lib:\$LIBS"
            [[ -d "/run/current-system/sw/lib" ]] && LIBS="/run/current-system/sw/lib:\$LIBS"
            [[ -d "/run/opengl-driver/lib" ]] && LIBS="/run/opengl-driver/lib:\$LIBS"
            exec env LD_LIBRARY_PATH="\$LIBS\''${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}" \\
              "${pythonProjectDir}/.venv/bin/python3" "\$@"
            WRAPPER_EOF
            chmod +x "$local_bin/python-venv"

            echo "✓ Python tools synced to ~/.local/bin"
          '';
      };
    };
}
