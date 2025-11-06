{ inputs, ... }:
{
  perSystem = { pkgs, lib, ... }:
    let
      lintScript = pkgs.writeShellApplication {
        name = "lint";
        runtimeInputs = with pkgs; [ statix deadnix nixpkgs-fmt gum ];
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

      pre-commit-check = inputs.git-hooks.lib.${pkgs.stdenv.hostPlatform.system}.run {
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
      formatter = pkgs.nixpkgs-fmt;

      checks = {
        pre-commit = pre-commit-check;
      };

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
          gum
          lintScript
          formatScript
        ];
      };
    };
}
