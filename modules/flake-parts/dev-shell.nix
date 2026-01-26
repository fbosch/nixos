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
          if gum spin --spinner dot --title "statix" -- statix check . > /tmp/statix-output 2>&1; then
            echo "$(gum style --foreground 2 '[OK]') statix"
          else
            echo "$(gum style --foreground 1 '[FAIL]') statix"
            cat /tmp/statix-output
            exit_code=1
          fi

          # Deadnix
          if gum spin --spinner dot --title "deadnix" -- deadnix --fail --no-lambda-pattern-names . > /tmp/deadnix-output 2>&1; then
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
          nixpkgs-fmt .
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

          # Format staged files
          staged_files=$(git diff --cached --name-only --diff-filter=ACM | grep '\.nix$' || true)

          if [ -n "$staged_files" ]; then
            echo "$staged_files" | xargs -r nixpkgs-fmt
            echo "$staged_files" | xargs -r git add
          fi

          # Run lint checks on entire repository
          ${lintScript}/bin/lint || exit_code=$?

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
