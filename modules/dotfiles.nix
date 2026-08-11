{ inputs, config, ... }:
let
  flakeConfig = config;
  homeManagerDotfiles =
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
in
{
  flake.modules.homeManager.dotfiles = homeManagerDotfiles;

  perSystem =
    { lib, pkgs, ... }:
    let
      dotfilesHomeConfig =
        (inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            homeManagerDotfiles
            {
              home = {
                username = "tester";
                homeDirectory = "/home/tester";
                stateVersion = "25.05";
              };
            }
          ];
        }).config;
      dotfilesActivation = dotfilesHomeConfig.home.activation.dotfiles;
      dotfilesScript = dotfilesActivation.data;
      bootstrapRevision = inputs.dotfiles.rev or "master";
      scriptLines = lib.splitString "\n" dotfilesScript;
      lineIndex =
        needle:
        let
          find =
            index: lines:
            if lines == [ ] then
              null
            else if lib.hasInfix needle (builtins.head lines) then
              index
            else
              find (index + 1) (builtins.tail lines);
        in
        find 0 scriptLines;
      checkoutIndex = lineIndex "checkout ${bootstrapRevision}";
      publishIndex = lineIndex ''mv "$BOOTSTRAP_REPO"'';
    in
    {
      nix-unit.tests.dotfilesActivation = {
        testActivationRestowsDotfiles = {
          expr = lib.hasInfix ''/bin/stow --restow --verbose --dir /home/tester/dotfiles --target "$HOME" .'' dotfilesScript;
          expected = true;
        };
        testBootstrapChecksOutPinnedRevision = {
          expr = lib.hasInfix "checkout ${bootstrapRevision}" dotfilesScript;
          expected = true;
        };
        testBootstrapPublishesOnlyAfterCheckout = {
          expr = checkoutIndex != null && publishIndex != null && checkoutIndex < publishIndex;
          expected = true;
        };
        testActivationValidatesCheckoutRoot = {
          expr = lib.all (fragment: lib.hasInfix fragment dotfilesScript) [
            "rev-parse --show-toplevel"
            "realpath /home/tester/dotfiles"
            "exit 1"
          ];
          expected = true;
        };
      };
    };
}
