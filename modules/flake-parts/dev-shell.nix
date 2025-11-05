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
          
          gum style --border rounded --padding "0 1" --bold "Linting NixOS configuration"
          echo
          
          # Statix check
          if gum spin --spinner dot --title "Running statix..." -- statix check . > /tmp/statix-output 2>&1; then
            gum style --foreground 2 "[PASS] statix"
          else
            gum style --foreground 1 "[FAIL] statix found issues"
            cat /tmp/statix-output
            exit_code=1
          fi
          echo
          
          # Deadnix check
          if gum spin --spinner dot --title "Running deadnix..." -- deadnix --fail --no-lambda-pattern-names . > /tmp/deadnix-output 2>&1; then
            gum style --foreground 2 "[PASS] deadnix"
          else
            gum style --foreground 1 "[FAIL] deadnix found unused code"
            cat /tmp/deadnix-output
            exit_code=1
          fi
          echo
          
          # Format check
          if gum spin --spinner dot --title "Checking formatting..." -- nixpkgs-fmt --check . > /tmp/fmt-output 2>&1; then
            gum style --foreground 2 "[PASS] All files properly formatted"
          else
            gum style --foreground 1 "[FAIL] Files need formatting"
            cat /tmp/fmt-output
            echo
            gum style --foreground 3 "Hint: Run 'nix run .#fmt' to auto-format"
            exit_code=1
          fi
          echo
          
          # Final result
          if [ $exit_code -ne 0 ]; then
            printf "LINT FAILED\n\nFix issues above and re-run 'nix run .#lint'" | gum style --border double --border-foreground 1 --padding "0 1" --bold
          else
            echo "ALL CHECKS PASSED" | gum style --border double --border-foreground 2 --padding "0 1" --bold
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
          gum
          lintScript
          formatScript
        ];
      };
    };
}
