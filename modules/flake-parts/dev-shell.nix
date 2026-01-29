_: {
  perSystem =
    { pkgs, ... }:
    let
      lintScript = pkgs.writeShellApplication {
        name = "lint";
        runtimeInputs = with pkgs; [
          statix
          deadnix
          nixpkgs-fmt
          gum
        ];
        text = ''
          set +e
          exit_code=0

          gum style --foreground 244 "Linting..."

          # Statix
          if gum spin --spinner dot --title "statix" -- statix check --ignore '.agents/**' '.opencode/skills/**' '.github/skills/**' . > /tmp/statix-output 2>&1; then
            echo "$(gum style --foreground 2 '[OK]') statix"
          else
            echo "$(gum style --foreground 1 '[FAIL]') statix"
            cat /tmp/statix-output
            echo "  $(gum style --foreground 3 '[HINT]') Run 'statix fix .' to auto-fix issues"
            exit_code=1
          fi

          # Deadnix
          if gum spin --spinner dot --title "deadnix" -- deadnix --fail --no-lambda-pattern-names --exclude '.agents' '.opencode/skills' '.github/skills' . > /tmp/deadnix-output 2>&1; then
            echo "$(gum style --foreground 2 '[OK]') deadnix"
          else
            echo "$(gum style --foreground 1 '[FAIL]') deadnix"
            cat /tmp/deadnix-output
            exit_code=1
          fi

          # Format
          if gum spin --spinner dot --title "format" -- nixpkgs-fmt --check . > /tmp/fmt-output 2>&1; then
            echo "$(gum style --foreground 2 '[OK]') format"
          else
            echo "$(gum style --foreground 1 '[FAIL]') format"
            cat /tmp/fmt-output
            echo "  $(gum style --foreground 3 '[HINT]') Run nix run .#fmt to fix"
            exit_code=1
          fi

          if [ $exit_code -ne 0 ]; then
            echo "$(gum style --foreground 1 '[ERROR]') Lint failed"
          else
            echo "$(gum style --foreground 2 '[DONE]') All checks passed"
          fi

          exit $exit_code
        '';
      };

      formatScript = pkgs.writeShellApplication {
        name = "fmt";
        runtimeInputs = with pkgs; [ nixpkgs-fmt ];
        text = ''
          # Format all Nix files except skill directories (including symlinks)
          find . -name '*.nix' -not -path './.agents/*' -not -path './.github/skills/*' -not -path './.opencode/skills/*' -exec nixpkgs-fmt {} +
        '';
      };

      precommitWrapper = pkgs.writeShellApplication {
        name = "pre-commit-wrapper";
        runtimeInputs = with pkgs; [
          git
          nixpkgs-fmt
          statix
          deadnix
          gum
        ];
        text = ''
          set +e
          exit_code=0

          gum style --foreground 244 "Pre-commit checks..."

          # Format staged files (exclude skill directories and symlinks)
          staged_files=$(git diff --cached --name-only --diff-filter=ACM | grep '\.nix$' | grep -v '^\.agents/' | grep -v '^\.github/skills/' | grep -v '^\.opencode/skills/' || true)

          if [ -n "$staged_files" ]; then
            if gum spin --spinner dot --title "format" -- sh -c "echo '$staged_files' | xargs -r nixpkgs-fmt"; then
              echo "$(gum style --foreground 2 '[OK]') format (auto-fixed)"
              echo "$staged_files" | xargs -r git add
            else
              echo "$(gum style --foreground 1 '[FAIL]') format"
              exit_code=1
            fi
          else
            echo "$(gum style --foreground 244 '[SKIP]') format (no .nix files staged)"
          fi

          # Statix - check entire repository
          # First try to auto-fix issues
          if [ -n "$staged_files" ]; then
            if gum spin --spinner dot --title "statix (fixing)" -- sh -c "echo '$staged_files' | xargs -r statix fix" > /tmp/statix-fix-output 2>&1; then
              # Re-stage fixed files
              echo "$staged_files" | xargs -r git add
              echo "$(gum style --foreground 3 '[FIXED]') statix auto-fixed issues"
            else
              echo "$(gum style --foreground 1 '[FAIL]') statix fix failed"
              cat /tmp/statix-fix-output
              exit_code=1
            fi
          fi

          # Now check for any remaining issues (only if fix succeeded or no files to fix)
          if [ $exit_code -eq 0 ]; then
            if gum spin --spinner dot --title "statix" -- statix check --ignore '.agents/**' '.opencode/skills/**' '.github/skills/**' . > /tmp/statix-output 2>&1; then
              echo "$(gum style --foreground 2 '[OK]') statix"
            else
              echo "$(gum style --foreground 1 '[FAIL]') statix"
              cat /tmp/statix-output
              echo "  $(gum style --foreground 3 '[HINT]') Some issues cannot be auto-fixed - please fix manually"
              exit_code=1
            fi
          fi

          # Deadnix - check entire repository
          if gum spin --spinner dot --title "deadnix" -- deadnix --fail --no-lambda-pattern-names --exclude '.agents' '.opencode/skills' '.github/skills' . > /tmp/deadnix-output 2>&1; then
            echo "$(gum style --foreground 2 '[OK]') deadnix"
          else
            echo "$(gum style --foreground 1 '[FAIL]') deadnix"
            cat /tmp/deadnix-output
            exit_code=1
          fi

          if [ $exit_code -ne 0 ]; then
            echo "$(gum style --foreground 1 '[ERROR]') Pre-commit checks failed"
          else
            echo "$(gum style --foreground 2 '[DONE]') All pre-commit checks passed"
          fi

          exit $exit_code
        '';
      };
    in
    {
      formatter = pkgs.nixpkgs-fmt;

      checks = { };

      apps = {
        lint = {
          type = "app";
          program = "${lintScript}/bin/lint";
          meta.description = "Run statix/deadnix/fmt checks";
        };
        fmt = {
          type = "app";
          program = "${formatScript}/bin/fmt";
          meta.description = "Format Nix files with nixpkgs-fmt";
        };
        pre-commit-wrapper = {
          type = "app";
          program = "${precommitWrapper}/bin/pre-commit-wrapper";
          meta.description = "Run pre-commit checks with formatting";
        };
      };

      devShells.default = pkgs.mkShell {
        shellHook = ''
                              # Install pre-commit hook wrapper (no hardcoded store paths)
                              if [ ! -f .git/hooks/pre-commit ]; then
                                mkdir -p .git/hooks
                                cat > .git/hooks/pre-commit << 'EOF'
          #!/usr/bin/env bash
          # Wrapper that always uses current flake environment
          exec nix run .#pre-commit-wrapper "$@"
          EOF
                                chmod +x .git/hooks/pre-commit
                                echo "Installed pre-commit hook"
                              fi
        '';
        packages = with pkgs; [
          statix
          deadnix
          nixpkgs-fmt
          gum
          lintScript
          formatScript
        ];
      };
    };
}
