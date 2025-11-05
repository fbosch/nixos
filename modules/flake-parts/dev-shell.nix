{ inputs, ... }:
{
  perSystem = { pkgs, lib, ... }:
    let
      lintScript = pkgs.writeShellApplication {
        name = "lint";
        runtimeInputs = with pkgs; [ statix deadnix nixpkgs-fmt ];
        text = ''
          exit_code=0
          
          echo "=== Running statix (Nix linter) ==="
          if ! statix check .; then
            echo "? statix found issues (see output above)"
            exit_code=1
          else
            echo "? statix passed"
          fi
          echo ""
          
          echo "=== Running deadnix (unused code detector) ==="
          if ! deadnix --fail --no-lambda-pattern-names .; then
            echo "? deadnix found unused code (see output above)"
            exit_code=1
          else
            echo "? deadnix passed"
          fi
          echo ""
          
          echo "=== Running nixpkgs-fmt (formatting check) ==="
          unformatted_files=$(nixpkgs-fmt --check . 2>&1 | grep -v "formatted" || true)
          if [ -n "$unformatted_files" ]; then
            echo "? The following files need formatting:"
            echo "$unformatted_files"
            echo ""
            echo "Run 'nix run .#fmt' to fix formatting issues"
            exit_code=1
          else
            echo "? All files are properly formatted"
          fi
          echo ""
          
          if [ $exit_code -ne 0 ]; then
            echo "=== LINT FAILED ==="
            echo "Please fix the issues above and run 'nix run .#lint' again"
          else
            echo "=== ALL CHECKS PASSED ==="
          fi
          
          exit $exit_code
        '';
      };

      formatScript = pkgs.writeShellApplication {
        name = "fmt";
        runtimeInputs = with pkgs; [ nixpkgs-fmt ];
        text = ''
          nixpkgs-fmt .
        '';
      };

      pre-commit-check = inputs.git-hooks.lib.${pkgs.system}.run {
        src = ./../..;
        hooks = {
          lint = {
            enable = true;
            entry = "${lintScript}/bin/lint";
            language = "system";
            files = "\\.nix$";
            pass_filenames = false;
          };
        };
      };
    in
    {
      apps = {
        lint = {
          type = "app";
          program = "${lintScript}/bin/lint";
        };
        fmt = {
          type = "app";
          program = "${formatScript}/bin/fmt";
        };
      };

      devShells.default = pkgs.mkShell {
        shellHook = ''
          ${pre-commit-check.shellHook}
        '';
        packages = with pkgs; [
          statix
          deadnix
          nixpkgs-fmt
          lintScript
          formatScript
        ];
      };
    };
}
