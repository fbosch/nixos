{ inputs, ... }:

{
  flake.modules.homeManager.dotfiles =
    { config
    , pkgs
    , lib
    , meta
    , ...
    }:
    let
      REPO = lib.escapeShellArg "${config.home.homeDirectory}/dotfiles";
      DOTFILES_REV = inputs.dotfiles.rev or "master";
      DOTFILES_URL = meta.dotfiles.url;
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

          # Ensure remote uses SSH instead of HTTPS
          CURRENT_URL=$(${pkgs.git}/bin/git -C ${REPO} remote get-url origin 2>/dev/null || echo "")
          if [[ "$CURRENT_URL" == https://github.com/* ]]; then
            SSH_URL=$(echo "$CURRENT_URL" | sed 's|https://github.com/|git@github.com:|')
            echo "Switching remote from HTTPS to SSH: $SSH_URL"
            $DRY_RUN_CMD ${pkgs.git}/bin/git -C ${REPO} remote set-url origin "$SSH_URL"
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
        readline
      ];
    };
}
