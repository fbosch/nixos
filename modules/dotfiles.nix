{ inputs, config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.homeManager.dotfiles =
    { config
    , pkgs
    , lib
    , hostMeta
    , ...
    }:
    let
      hmConfig = config;
      REPO = lib.escapeShellArg "${hmConfig.home.homeDirectory}/dotfiles";
      DOTFILES_REV = inputs.dotfiles.rev or "master";
      DOTFILES_URL = flakeConfig.flake.meta.dotfiles.url;
      GH = "${pkgs.gh}/bin/gh";
      isCorporateHost = hostMeta.corporate or false;
      stowFlags = if isCorporateHost then "--restow --verbose" else "--restow --adopt --verbose";
    in
    # Manages dotfiles via git clone + GNU Stow.
      # Clones the dotfiles repo (pinned to a flake input revision) on first activation,
      # then symlinks everything into $HOME with stow on every activation.
    {
      home.packages = with pkgs; [
        stow
      ];
      home.activation = {
        # Phase 1: ensure the dotfiles repo is present and uses SSH.

        # Runs after writeBoundary so the home directory structure exists.
        setupDotfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          set -euo pipefail

          github_authenticated=false
          if ${GH} auth status --hostname github.com >/dev/null 2>&1; then
            github_authenticated=true
          fi

          if [ -d ${REPO}/.git ]; then
            echo "Dotfiles repository already exists, skipping checkout to preserve local changes..."
          else
            clone_url=${lib.escapeShellArg DOTFILES_URL}
            if [ "$github_authenticated" = true ] && [[ "$clone_url" == https://github.com/* ]]; then
              clone_url=$(echo "$clone_url" | sed 's|https://github.com/|git@github.com:|')
            fi

            echo "Cloning dotfiles repository at revision ${DOTFILES_REV}..."
            $DRY_RUN_CMD ${pkgs.git}/bin/git clone "$clone_url" ${REPO}
            $DRY_RUN_CMD ${pkgs.git}/bin/git -C ${REPO} checkout ${DOTFILES_REV}
          fi

          # Use SSH when GitHub authentication is available; HTTPS remains a public bootstrap fallback.
          CURRENT_URL=$(${pkgs.git}/bin/git -C ${REPO} remote get-url origin 2>/dev/null || echo "")
          if [ "$github_authenticated" = true ] && [[ "$CURRENT_URL" == https://github.com/* ]]; then
            SSH_URL=$(echo "$CURRENT_URL" | sed 's|https://github.com/|git@github.com:|')
            echo "Switching remote from HTTPS to SSH: $SSH_URL"
            $DRY_RUN_CMD ${pkgs.git}/bin/git -C ${REPO} remote set-url origin "$SSH_URL"
          elif [ "$github_authenticated" = false ] && [[ "$CURRENT_URL" == git@github.com:* ]]; then
            HTTPS_URL=$(echo "$CURRENT_URL" | sed 's|git@github.com:|https://github.com/|')
            echo "Switching remote from SSH to HTTPS: $HTTPS_URL"
            $DRY_RUN_CMD ${pkgs.git}/bin/git -C ${REPO} remote set-url origin "$HTTPS_URL"
          fi
        '';

        # Phase 2: symlink dotfiles into $HOME.
        # Waits for both setupDotfiles (repo ready) and linkGeneration (HM links written)
        # so stow doesn't conflict with Home Manager's own symlinks.
        stowDotFiles = lib.hm.dag.entryAfter [ "setupDotfiles" "linkGeneration" ] ''
          set -euo pipefail

          cd ${REPO}
          CURRENT_REV=$(${pkgs.git}/bin/git rev-parse --short HEAD 2>/dev/null || echo "unknown")
          echo "Stowing dotfiles from current revision: $CURRENT_REV"
          $DRY_RUN_CMD ${pkgs.stow}/bin/stow ${stowFlags} -t "$HOME" .
        '';
      };
    };
}
