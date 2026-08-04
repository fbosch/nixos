{ inputs, ... }:
{
  # We keep pre-commit-hooks integration for flake checks.
  # Local git hook installation is handled by devenv.
  imports = [
    inputs.pre-commit-hooks.flakeModule
    inputs.treefmt-nix.flakeModule
  ];

  perSystem =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      lintScript = pkgs.writeShellApplication {
        name = "lint";
        runtimeInputs = with pkgs; [
          statix
          deadnix
          config.treefmt.build.wrapper
          nixpkgs-fmt
          shfmt
          actionlint
          shellcheck
          fish
          gum
        ];
        text = builtins.readFile ../../scripts/lint.sh;
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
            shfmt = {
              enable = true;
              settings.indent = 2;
            };
            statix = {
              enable = true;
              settings.ignore = [ "{.agents,.opencode/skills,.github/skills}/**" ];
            };
            deadnix = {
              enable = true;
              settings.noLambdaPatternNames = true;
            };
            actionlint.enable = true;
            shellcheck.enable = true;
            check-added-large-files = {
              enable = true;
              excludes = [ "^modules/desktop/display-manager/" ];
            };
            check-merge-conflicts.enable = true;
            check-symlinks.enable = true;
            end-of-file-fixer.enable = true;
            pngcheck = {
              enable = true;
              entry = "${pkgs.pngcheck}/bin/pngcheck";
              files = "\\.png$";
            };
            ripsecrets.enable = true;
            trim-trailing-whitespace = {
              enable = true;
              excludes = [ "\\.md$" ];
            };
          };
        };
      };

      treefmt = {
        programs = {
          nixpkgs-fmt.enable = true;
          shfmt = {
            enable = true;
            indent_size = 2;
            simplify = true;
          };
        };
        settings.formatter = {
          nixpkgs-fmt.excludes = [
            ".agents/**/*.nix"
            ".github/skills/**/*.nix"
            ".opencode/skills/**/*.nix"
          ];
          shfmt.includes = [ "*.sh" ];
        };
      };

      apps = {
        lint = {
          type = "app";
          program = "${lintScript}/bin/lint";
          meta.description = "Run treefmt, statix, deadnix, actionlint, and shellcheck";
        };
        fmt = {
          type = "app";
          program = "${config.treefmt.build.wrapper}/bin/treefmt";
          meta.description = "Format files via treefmt";
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
        packages =
          (with pkgs; [
            just
            git
            nil
            nixd
            statix
            deadnix
            actionlint
            shellcheck
            gum
            pre-commit
            lintScript
          ])
          ++ [ config.treefmt.build.wrapper ]
          ++ lib.attrValues config.treefmt.build.programs;
        shellHook = ''
          ${config.pre-commit.installationScript}

          if [ ! -e .git/hooks/pre-commit-checks ]; then
            mv .git/hooks/pre-commit .git/hooks/pre-commit-checks
          fi

           ln -sf "$(git rev-parse --show-toplevel)/scripts/pre-commit-wrapper.sh" .git/hooks/pre-commit
           ln -sf "$(git rev-parse --show-toplevel)/scripts/pre-push-wrapper.sh" .git/hooks/pre-push
        '';
      };
    };
}
