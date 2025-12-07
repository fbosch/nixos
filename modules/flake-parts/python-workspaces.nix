{ inputs, ... }:

{
  # Python workspace packages built using uv2nix
  # 
  # This module exposes Python virtual environments as flake packages.
  # Workspaces are defined here and built using the mkPythonWorkspace helper
  #
  # Add new workspaces to the `workspaces` attrset below.
  # They will be available as pkgs.local.<workspace-name>

  perSystem = { pkgs, lib, ... }:
    let
      # Helper for building Python venvs from uv workspaces
      # Defined here to have access to pkgs and lib from perSystem context
      mkPythonWorkspace =
        { name
        , workspaceRoot
        , python ? pkgs.python312
        , sourcePreference ? "wheel" # "wheel" or "sdist"
        }:
        let
          # Load the uv workspace
          workspace = inputs.uv2nix.lib.workspace.loadWorkspace {
            inherit workspaceRoot;
          };

          # Create overlay for Python packages from workspace
          overlay = workspace.mkPyprojectOverlay {
            inherit sourcePreference;
          };

          # Python set with all overlays applied
          pythonSet = (pkgs.callPackage inputs.pyproject-nix.build.packages {
            inherit python;
          }).overrideScope (
            lib.composeManyExtensions [
              inputs.pyproject-build-systems.overlays.default
              overlay
            ]
          );

          # Create the virtual environment with all dependencies
          venv = pythonSet.mkVirtualEnv "${name}-venv" workspace.deps.default;

        in
        venv;

      # Define all Python workspaces here
      workspaces = {
        ocr-tools = mkPythonWorkspace {
          name = "ocr-tools";
          workspaceRoot = "${inputs.self}/modules/development/workspaces/ocr-tools";
        };

        # Add more workspaces here as needed:
        # my-app = mkPythonWorkspace {
        #   name = "my-app";
        #   workspaceRoot = "${inputs.self}/modules/development/workspaces/my-app";
        #   python = pkgs.python311; # Optional: override Python version
        # };
      };

    in
    {
      packages = workspaces;
    };
}
