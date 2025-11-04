{ inputs, ... }:
{
  perSystem = { pkgs, lib, ... }:
    let
      lintScript = pkgs.writeShellApplication {
        name = "lint";
        runtimeInputs = with pkgs; [ statix deadnix nixpkgs-fmt ];
        text = ''
          set -e
          echo "Running statix..."
          statix check .
          echo "Running deadnix..."
          deadnix --fail --no-lambda-pattern-names .
          echo "Running nixpkgs-fmt..."
          nixpkgs-fmt --check .
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
