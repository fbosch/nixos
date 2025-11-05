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
          
          gum style --bold --border rounded --padding "0 1" "Linting NixOS Configuration"
          echo
          
          # Statix
          if gum spin --spinner dot --title "Running statix..." -- statix check . > /tmp/statix-output 2>&1; then
            printf $'\u2713 statix\n' | gum style --foreground 2
          else
            printf $'\u2717 statix\n' | gum style --foreground 1
            cat /tmp/statix-output
            exit_code=1
          fi
          
          # Deadnix
          if gum spin --spinner dot --title "Running deadnix..." -- deadnix --fail --no-lambda-pattern-names . > /tmp/deadnix-output 2>&1; then
            printf $'\u2713 deadnix\n' | gum style --foreground 2
          else
            printf $'\u2717 deadnix\n' | gum style --foreground 1
            cat /tmp/deadnix-output
            exit_code=1
          fi
          
          # Format
          if gum spin --spinner dot --title "Checking format..." -- nixpkgs-fmt --check . > /tmp/fmt-output 2>&1; then
            printf $'\u2713 format\n' | gum style --foreground 2
          else
            printf $'\u2717 format\n' | gum style --foreground 1
            cat /tmp/fmt-output
            printf $'  \u2192 Run nix run .#fmt to fix\n' | gum style --foreground 3
            exit_code=1
          fi
          
          echo
          if [ $exit_code -ne 0 ]; then
            gum style --foreground 1 --bold "Failed"
          else
            gum style --foreground 2 --bold "All checks passed"
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
