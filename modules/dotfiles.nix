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
      DOTFILES_FALLBACK = lib.escapeShellArg inputs.dotfiles.outPath;
      DOTFILES_BOOTSTRAP_REV = inputs.dotfiles.rev or "master";
      DOTFILES_BOOTSTRAP_URL = lib.escapeShellArg flakeConfig.flake.meta.dotfiles.url;
      stowFlags = "--restow --verbose";
    in
    {
      home.packages = with pkgs; [
        stow
      ];
      home.activation = {
        # Dotfiles activation flow:
        #
        #   Home Manager creates its links
        #                │
        #                v
        #         checkout exists?
        #          ┌─────┴─────┐
        #         no          yes
        #          │            │
        #          v            v
        #   stow flake input   independent Git root?
        #   + retry clone        ┌────┴────┐
        #          │            no        yes
        #          │             │          │
        #          │             v          v
        #          │           refuse   preserve mutable checkout
        #          │                        │
        #          └───────────┬────────────┘
        #                      v
        #       generation changed or bootstrapped?
        #                ┌─────┴─────┐
        #               yes         no
        #                │           │
        #                v           v
        #        GNU Stow checkout  skip restow
        #
        # Existing checkouts are reconciled separately by git_pull_system_repos.
        dotfiles = lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
          set -euo pipefail

          did_bootstrap=false
          if [ ! -e ${REPO} ]; then
            echo "Bootstrapping dotfiles repository at revision ${DOTFILES_BOOTSTRAP_REV}..."
            if [ -n "$DRY_RUN_CMD" ]; then
              echo "Would stow the flake input, clone the mutable checkout, and publish ${REPO}."
            else
              echo "Stowing the pinned flake input while bootstrapping the mutable checkout..."
              ${pkgs.stow}/bin/stow ${stowFlags} --dir ${DOTFILES_FALLBACK} --target "$HOME" .

              BOOTSTRAP_PARENT=$(${pkgs.coreutils}/bin/mktemp -d ${HOME_DIR}/.dotfiles-bootstrap.XXXXXX)
              BOOTSTRAP_REPO="$BOOTSTRAP_PARENT/dotfiles"
              cleanup_bootstrap() {
                ${pkgs.coreutils}/bin/rm -rf "$BOOTSTRAP_PARENT"
              }
              trap cleanup_bootstrap EXIT

              clone_deadline=$((SECONDS + 60))
              until ${pkgs.git}/bin/git ls-remote ${DOTFILES_BOOTSTRAP_URL} HEAD >/dev/null 2>&1; do
                if ((SECONDS >= clone_deadline)); then
                  echo "Timed out waiting for network access to the dotfiles repository." >&2
                  exit 1
                fi
                ${pkgs.coreutils}/bin/sleep 1
              done

              ${pkgs.git}/bin/git clone ${DOTFILES_BOOTSTRAP_URL} "$BOOTSTRAP_REPO"
              ${pkgs.git}/bin/git -C "$BOOTSTRAP_REPO" checkout ${DOTFILES_BOOTSTRAP_REV}
              ${pkgs.stow}/bin/stow --delete --verbose --dir ${DOTFILES_FALLBACK} --target "$HOME" .
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
      dotfilesInputPath = builtins.unsafeDiscardStringContext inputs.dotfiles.outPath;
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
      fallbackStowIndex = lineIndex "/bin/stow --restow --verbose --dir ${dotfilesInputPath}";
      fallbackDeleteIndex = lineIndex "/bin/stow --delete --verbose --dir ${dotfilesInputPath}";
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
        testBootstrapWaitsForRepository = {
          expr = lib.all (fragment: lib.hasInfix fragment dotfilesScript) [
            "clone_deadline=$((SECONDS + 60))"
            "ls-remote https://github.com/fbosch/dotfiles HEAD"
            "Timed out waiting for network access to the dotfiles repository."
          ];
          expected = true;
        };
        testBootstrapUsesFlakeInputUntilCheckoutExists = {
          expr =
            fallbackStowIndex != null
            && fallbackDeleteIndex != null
            && publishIndex != null
            && fallbackStowIndex < fallbackDeleteIndex
            && fallbackDeleteIndex < publishIndex;
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
