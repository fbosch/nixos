{ inputs, config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.homeManager.dotfiles =
    { config
    , pkgs
    , lib
    , ...
    }:
    let
      hmConfig = config;
      HOME_DIR = lib.escapeShellArg hmConfig.home.homeDirectory;
      REPO = lib.escapeShellArg "${hmConfig.home.homeDirectory}/dotfiles";
      DOTFILES_BOOTSTRAP_REV = inputs.dotfiles.rev or "master";
      DOTFILES_BOOTSTRAP_URL = lib.escapeShellArg flakeConfig.flake.meta.dotfiles.url;
      stowFlags = "--restow --verbose";
    in
    # Manages dotfiles via git clone + GNU Stow.
      # The flake revision is used only to bootstrap an absent checkout. Existing
      # checkouts remain mutable and are reconciled by git_pull_system_repos.
    {
      home.packages = with pkgs; [
        stow
      ];
      home.activation = {
        # Phase 1: bootstrap the checkout only when its path is absent.
        setupDotfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          set -euo pipefail

          DOTFILES_BOOTSTRAPPED=false
          if [ ! -e ${REPO} ]; then
            echo "Bootstrapping dotfiles repository at revision ${DOTFILES_BOOTSTRAP_REV}..."
            if [ -n "$DRY_RUN_CMD" ]; then
              $DRY_RUN_CMD ${pkgs.git}/bin/git clone ${DOTFILES_BOOTSTRAP_URL} ${REPO}
              $DRY_RUN_CMD ${pkgs.git}/bin/git -C ${REPO} checkout ${DOTFILES_BOOTSTRAP_REV}
              $DRY_RUN_CMD ${pkgs.git}/bin/git -C ${REPO} remote set-url origin ${DOTFILES_BOOTSTRAP_URL}
            else
              BOOTSTRAP_PARENT=$(${pkgs.coreutils}/bin/mktemp -d ${HOME_DIR}/.dotfiles-bootstrap.XXXXXX)
              BOOTSTRAP_REPO="$BOOTSTRAP_PARENT/dotfiles"
              cleanup_bootstrap() {
                ${pkgs.coreutils}/bin/rm -rf "$BOOTSTRAP_PARENT"
              }
              trap cleanup_bootstrap EXIT

              ${pkgs.git}/bin/git clone ${DOTFILES_BOOTSTRAP_URL} "$BOOTSTRAP_REPO"
              ${pkgs.git}/bin/git -C "$BOOTSTRAP_REPO" checkout ${DOTFILES_BOOTSTRAP_REV}
              ${pkgs.git}/bin/git -C "$BOOTSTRAP_REPO" remote set-url origin ${DOTFILES_BOOTSTRAP_URL}
              ${pkgs.coreutils}/bin/mv "$BOOTSTRAP_REPO" ${REPO}
              ${pkgs.coreutils}/bin/rmdir "$BOOTSTRAP_PARENT"
              trap - EXIT
            fi
            DOTFILES_BOOTSTRAPPED=true
          else
            if ! REPO_TOPLEVEL=$(${pkgs.git}/bin/git -C ${REPO} rev-parse --show-toplevel 2>/dev/null); then
              echo "Expected ${REPO} to be a Git checkout; refusing to replace existing files." >&2
              exit 1
            fi
            if [ "$REPO_TOPLEVEL" != "$(${pkgs.coreutils}/bin/realpath ${REPO})" ]; then
              echo "Expected ${REPO} to be the root of its Git checkout; refusing to use a parent repository." >&2
              exit 1
            fi
            echo "Using existing mutable dotfiles checkout without Git reconciliation."
          fi
        '';

        # Phase 2: symlink dotfiles into $HOME.
        # Waits for both setupDotfiles (repo ready) and linkGeneration (HM links written)
        # so stow doesn't conflict with Home Manager's own symlinks.
        stowDotFiles = lib.hm.dag.entryAfter [ "setupDotfiles" "linkGeneration" ] ''
          set -euo pipefail

          if [ -n "''${oldGenPath:-}" ] && [ "''${oldGenPath}" = "''${newGenPath:-}" ] && [ "''${DOTFILES_BOOTSTRAPPED:-false}" = false ]; then
            echo "Home Manager generation unchanged, skipping dotfiles stow"
          else
            if [ -d ${REPO} ]; then
              CURRENT_REV=$(${pkgs.git}/bin/git -C ${REPO} rev-parse --short HEAD 2>/dev/null || echo "unknown")
              echo "Stowing dotfiles from current revision: $CURRENT_REV"
            else
              echo "Stowing bootstrapped dotfiles..."
            fi
            $DRY_RUN_CMD ${pkgs.stow}/bin/stow ${stowFlags} --dir ${REPO} --target "$HOME" .
          fi
        '';
      };
    };
}
