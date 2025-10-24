{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  REPO = lib.escapeShellArg "${config.home.homeDirectory}/dotfiles";
  DOTFILES_REV = inputs.dotfiles.rev or "master";
  DOTFILES_URL = "https://github.com/fbosch/dotfiles";
in
{
  home = {
    activation = {
      # Clone repository with revision from flake.lock
      # only if there is not already a git repository instantiated
      # this preserves any local changes or customizations between rebuilds
      setupDotfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        set -euo pipefail

        if [ ! -d ${REPO}/.git ]; then
          echo "Cloning dotfiles repository at revision ${DOTFILES_REV}..."
          $DRY_RUN_CMD ${pkgs.git}/bin/git clone ${DOTFILES_URL} ${REPO}
          $DRY_RUN_CMD ${pkgs.git}/bin/git -C ${REPO} checkout ${DOTFILES_REV}
        else
          echo "Dotfiles repository already exists, skipping checkout to preserve local changes..."
        fi
      '';

      # create symlinks from dotfiles to home directory
      stowDotFiles = lib.hm.dag.entryAfter [ "setupDotfiles" "linkGeneration" ] ''
        set -euo pipefail
        cd ${REPO}
        CURRENT_REV=$(${pkgs.git}/bin/git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        echo "Stowing dotfiles from current revision: $CURRENT_REV"
        $DRY_RUN_CMD ${pkgs.stow}/bin/stow --adopt --restow --verbose -t "$HOME" .
      '';
    };

    packages = with pkgs; [
      stow
    ];
  };
}
