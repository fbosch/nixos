{ inputs, ... }:
{
  # We keep pre-commit-hooks integration for flake checks.
  # Local git hook installation is handled by a custom gum-based wrapper.
  imports = [
    inputs.pre-commit-hooks.flakeModule
  ];

  perSystem =
    { config, pkgs, ... }:
    let
      lintScript = pkgs.writeShellApplication {
        name = "lint";
        runtimeInputs = with pkgs; [
          statix
          deadnix
          treefmt
          nixpkgs-fmt
          shfmt
          actionlint
          shellcheck
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
          if gum spin --spinner dot --title "format" -- treefmt --no-cache --fail-on-change > /tmp/fmt-output 2>&1; then
            echo "$(gum style --foreground 2 '[OK]') format"
          else
            echo "$(gum style --foreground 1 '[FAIL]') format"
            cat /tmp/fmt-output
            echo "  $(gum style --foreground 3 '[HINT]') Run nix run .#fmt to fix"
            exit_code=1
          fi

          # actionlint
          if gum spin --spinner dot --title "actionlint" -- actionlint -shellcheck= > /tmp/actionlint-output 2>&1; then
            echo "$(gum style --foreground 2 '[OK]') actionlint"
          else
            echo "$(gum style --foreground 1 '[FAIL]') actionlint"
            cat /tmp/actionlint-output
            exit_code=1
          fi

          # Shell script lint
          shell_files=$(find scripts configs -type f -name '*.sh' 2>/dev/null || true)
          if [ -n "$shell_files" ]; then
            if gum spin --spinner dot --title "shellcheck" -- sh -c "printf '%s\n' \"$shell_files\" | xargs -r shellcheck -S error" > /tmp/shellcheck-output 2>&1; then
              echo "$(gum style --foreground 2 '[OK]') shellcheck"
            else
              echo "$(gum style --foreground 1 '[FAIL]') shellcheck"
              cat /tmp/shellcheck-output
              exit_code=1
            fi
          else
            echo "$(gum style --foreground 244 '[SKIP]') shellcheck (no shell files found)"
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
        runtimeInputs = with pkgs; [
          treefmt
          nixpkgs-fmt
          shfmt
        ];
        text = ''
          treefmt --no-cache
        '';
      };

      precommitWrapper = pkgs.writeShellApplication {
        name = "pre-commit-wrapper";
        runtimeInputs = with pkgs; [
          git
          treefmt
          nixpkgs-fmt
          shfmt
          statix
          deadnix
          actionlint
          shellcheck
          gum
        ];
        text = ''
          set +e
          exit_code=0

          gum style --foreground 244 "Pre-commit checks..."

          # Format staged files (excluding skill directories)
          staged_files=$(git diff --cached --name-only --diff-filter=ACM | grep -v '^\.agents/' | grep -v '^\.github/skills/' | grep -v '^\.opencode/skills/' || true)

          if [ -n "$staged_files" ]; then
            if gum spin --spinner dot --title "format" -- sh -c "printf '%s\n' \"$staged_files\" | xargs -r treefmt --no-cache"; then
              echo "$(gum style --foreground 2 '[OK]') format (auto-fixed)"
              echo "$staged_files" | xargs -r git add
            else
              echo "$(gum style --foreground 1 '[FAIL]') format"
              exit_code=1
            fi
          else
            echo "$(gum style --foreground 244 '[SKIP]') format (no staged files)"
          fi

          # Statix
          # First try to auto-fix issues
          if [ -n "$staged_files" ]; then
            if gum spin --spinner dot --title "statix (fixing)" -- sh -c "printf '%s\n' \"$staged_files\" | xargs -r -n 1 statix fix" > /tmp/statix-fix-output 2>&1; then
              # Check if anything was actually fixed
              if [ -s /tmp/statix-fix-output ]; then
                # Re-stage fixed files
                echo "$staged_files" | xargs -r git add
                echo "$(gum style --foreground 3 '[FIXED]') statix auto-fixed issues"
              fi
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

          # Deadnix
          if gum spin --spinner dot --title "deadnix" -- deadnix --fail --no-lambda-pattern-names --exclude '.agents' '.opencode/skills' '.github/skills' . > /tmp/deadnix-output 2>&1; then
            echo "$(gum style --foreground 2 '[OK]') deadnix"
          else
            echo "$(gum style --foreground 1 '[FAIL]') deadnix"
            cat /tmp/deadnix-output
            exit_code=1
          fi

          # actionlint - check staged workflow changes
          staged_workflows=$(git diff --cached --name-only --diff-filter=ACM | grep -E '^\.github/workflows/.*\.(yml|yaml)$' || true)
          if [ -n "$staged_workflows" ]; then
            if gum spin --spinner dot --title "actionlint" -- actionlint -shellcheck= > /tmp/actionlint-output 2>&1; then
              echo "$(gum style --foreground 2 '[OK]') actionlint"
            else
              echo "$(gum style --foreground 1 '[FAIL]') actionlint"
              cat /tmp/actionlint-output
              exit_code=1
            fi
          else
            echo "$(gum style --foreground 244 '[SKIP]') actionlint (no workflows staged)"
          fi

          # Shell script lint - check staged shell script changes
          staged_shell=$(git diff --cached --name-only --diff-filter=ACM | grep '\.sh$' || true)
          if [ -n "$staged_shell" ]; then
            if gum spin --spinner dot --title "shellcheck" -- sh -c "printf '%s\n' \"$staged_shell\" | xargs -r shellcheck -S error" > /tmp/shellcheck-output 2>&1; then
              echo "$(gum style --foreground 2 '[OK]') shellcheck"
            else
              echo "$(gum style --foreground 1 '[FAIL]') shellcheck"
              cat /tmp/shellcheck-output
              exit_code=1
            fi
          else
            echo "$(gum style --foreground 244 '[SKIP]') shellcheck (no shell scripts staged)"
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
      # Configure pre-commit hooks
      pre-commit = {
        check.enable = true;
        settings = {
          excludes = [
            "^\.?/?\.agents/"
            "^\.?/?\.opencode/skills/"
            "^\.?/?\.github/skills/"
          ];
          hooks = {
            treefmt.enable = true;
            statix = {
              enable = true;
              settings.ignore = [
                ".agents"
                ".opencode/skills"
                ".github/skills"
              ];
            };
            deadnix = {
              enable = true;
              settings.noLambdaPatternNames = true;
            };
            actionlint.enable = true;
            shellcheck.enable = true;
            check-added-large-files.enable = true;
            check-merge-conflicts.enable = true;
            check-symlinks.enable = true;
            end-of-file-fixer.enable = true;
            ripsecrets.enable = true;
            trim-trailing-whitespace.enable = true;
          };
        };
      };

      formatter = formatScript;

      apps = {
        lint = {
          type = "app";
          program = "${lintScript}/bin/lint";
          meta.description = "Run treefmt, statix, deadnix, actionlint, and shellcheck";
        };
        fmt = {
          type = "app";
          program = "${formatScript}/bin/fmt";
          meta.description = "Format files via treefmt";
        };
        pre-commit-wrapper = {
          type = "app";
          program = "${precommitWrapper}/bin/pre-commit-wrapper";
          meta.description = "Run staged pre-commit checks with treefmt and linters";
        };
      };

      devShells.default = pkgs.mkShell {
        shellHook = ''
                    # Install custom pre-commit hook with nice formatting
                    if [ ! -f .git/hooks/pre-commit ] || ! grep -q "pre-commit-wrapper" .git/hooks/pre-commit 2>/dev/null; then
                      mkdir -p .git/hooks
                      cat > .git/hooks/pre-commit << 'EOF'
          #!/usr/bin/env bash
          # Custom pre-commit hook with nice formatting
          exec nix run .#pre-commit-wrapper "$@"
          EOF
                      chmod +x .git/hooks/pre-commit
                      echo "$(${pkgs.gum}/bin/gum style --foreground 2 '[OK]') Installed pre-commit hook with nice formatting"
                    fi
        '';
        packages = with pkgs; [
          statix
          deadnix
          treefmt
          nixpkgs-fmt
          shfmt
          actionlint
          shellcheck
          gum
          lintScript
          formatScript
        ];
      };
    };
}
