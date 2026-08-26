{ inputs, ... }:
{
  # git-hooks.nix is the canonical hook configuration for local checks and CI.
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
          nix
        ];
        text = builtins.readFile ../../scripts/dev/lint.sh;
      };

      gitHookRunner = pkgs.writeShellApplication {
        name = "nixos-git-hook";
        runtimeInputs = [
          config.pre-commit.settings.package
          pkgs.git
        ];
        text = ''
          hook_type="''${1:-}"
          shift || true

          case "$hook_type" in
            pre-commit | pre-push) ;;
            *)
              echo "nixos-git-hook: unsupported hook type: $hook_type" >&2
              exit 2
              ;;
          esac

          repo_root=$(git rev-parse --show-toplevel)
          cd "$repo_root"
          exec ${lib.getExe config.pre-commit.settings.package} hook-impl \
            --config=${config.pre-commit.settings.configFile} \
            --hook-type="$hook_type" \
            --hook-dir="$repo_root/.githooks" \
            -- "$@"
        '';
      };

      installScript = pkgs.writeShellApplication {
        name = "bootstrap-machine";
        runtimeInputs = with pkgs; [
          gh
          git
          gum
          nix
          openssh
          qrencode
        ];
        text = builtins.readFile ../../scripts/bootstrap/bootstrap-machine.sh;
      };

      rotateGpgGistScript = pkgs.writeShellApplication {
        name = "rotate-gpg-gist";
        runtimeInputs = with pkgs; [
          gh
          gnupg
          xkcdpass
        ];
        text = builtins.readFile ../../scripts/maintenance/rotate-gpg-gist.sh;
      };
    in
    {
      # Configure pre-commit hooks
      pre-commit = {
        check.enable = true;
        settings = {
          install.enable = false;
          package = pkgs.prek;
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
            gitHookRunner
            lintScript
            qrencode
          ])
          ++ [ config.treefmt.build.wrapper ]
          ++ lib.attrValues config.treefmt.build.programs;
        shellHook = ''
          export NIXOS_GIT_HOOK_ROOT="$(git rev-parse --show-toplevel)"
        '';
      };
    };
}
