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
        # Bootstrap after Home Manager creates its links, then restow only when
        # the generation changed or bootstrap created the checkout.
        dotfiles = lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
          set -euo pipefail

          did_bootstrap=false
          if [ ! -e ${REPO} ]; then
            echo "Bootstrapping dotfiles repository at revision ${DOTFILES_BOOTSTRAP_REV}..."
            if [ -n "$DRY_RUN_CMD" ]; then
              echo "Would clone, check out the bootstrap revision, and publish ${REPO}."
            else
              BOOTSTRAP_PARENT=$(${pkgs.coreutils}/bin/mktemp -d ${HOME_DIR}/.dotfiles-bootstrap.XXXXXX)
              BOOTSTRAP_REPO="$BOOTSTRAP_PARENT/dotfiles"
              cleanup_bootstrap() {
                ${pkgs.coreutils}/bin/rm -rf "$BOOTSTRAP_PARENT"
              }
              trap cleanup_bootstrap EXIT

              ${pkgs.git}/bin/git clone ${DOTFILES_BOOTSTRAP_URL} "$BOOTSTRAP_REPO"
              ${pkgs.git}/bin/git -C "$BOOTSTRAP_REPO" checkout ${DOTFILES_BOOTSTRAP_REV}
              ${pkgs.coreutils}/bin/mv "$BOOTSTRAP_REPO" ${REPO}
              ${pkgs.coreutils}/bin/rmdir "$BOOTSTRAP_PARENT"
              trap - EXIT
            fi
            did_bootstrap=true
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

          if [ -n "''${oldGenPath:-}" ] && [ "''${oldGenPath}" = "''${newGenPath:-}" ] && [ "$did_bootstrap" = false ]; then
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
