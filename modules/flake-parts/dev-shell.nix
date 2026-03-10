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
        text = builtins.readFile ../../scripts/lint.sh;
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
        text = builtins.readFile ../../scripts/pre-commit-wrapper.sh;
      };

      installScript = pkgs.writeShellApplication {
        name = "bootstrap-machine";
        runtimeInputs = with pkgs; [
          gh
          git
          gum
        ];
        text = builtins.readFile ../../scripts/bootstrap-machine.sh;
      };

      rotateGpgGistScript = pkgs.writeShellApplication {
        name = "rotate-gpg-gist";
        runtimeInputs = with pkgs; [
          gh
          gnupg
          xkcdpass
        ];
        text = builtins.readFile ../../scripts/rotate-gpg-gist.sh;
      };

      installPreCommitHookScript = pkgs.writeShellApplication {
        name = "install-pre-commit-hook";
        runtimeInputs = with pkgs; [
          gum
        ];
        text = builtins.readFile ../../scripts/install-pre-commit-hook.sh;
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
            nixpkgs-fmt.enable = true;
            shfmt.enable = true;
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
            trim-trailing-whitespace = {
              enable = true;
              excludes = [ "\\.md$" ];
            };
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
        install = {
          type = "app";
          program = "${installScript}/bin/bootstrap-machine";
          meta.description = "Bootstrap a fresh NixOS host and copy /etc/nixos config";
        };
        rotate-gpg-gist = {
          type = "app";
          program = "${rotateGpgGistScript}/bin/rotate-gpg-gist";
          meta.description = "Rotate the encrypted GPG backup gist from the current local key";
        };
      };

      devShells.default = pkgs.mkShell {
        shellHook = ''
          ${installPreCommitHookScript}/bin/install-pre-commit-hook
        '';
        packages = with pkgs; [
          just
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
