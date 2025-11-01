{ inputs, ... }:

{
  flake.modules.homeManager.dotfiles = { config, pkgs, lib, ... }:
    let
      REPO = lib.escapeShellArg "${config.home.homeDirectory}/dotfiles";
      DOTFILES_REV = inputs.dotfiles.rev or "master";
      DOTFILES_URL = "https://github.com/fbosch/dotfiles";
    in
    {
      home.activation = {
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

        stowDotFiles = lib.hm.dag.entryAfter [ "setupDotfiles" "linkGeneration" ] ''
          set -euo pipefail
          cd ${REPO}
          CURRENT_REV=$(${pkgs.git}/bin/git rev-parse --short HEAD 2>/dev/null || echo "unknown")
          echo "Stowing dotfiles from current revision: $CURRENT_REV"
          $DRY_RUN_CMD ${pkgs.stow}/bin/stow --restow --verbose -t "$HOME" .
        '';
      };

      home.packages = with pkgs; [
        stow
      ];
    };
}
