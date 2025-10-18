{ config, pkgs, lib, ... }:
let
  REPO = lib.escapeShellArg "${config.home.homeDirectory}/dotfiles";
  URL = lib.escapeShellArg "https://github.com/fbosch/dotfiles";
in
{
  home.activation.setupDotfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -euo pipefail
    
    if [ ! -d ${REPO}/.git ]; then
      $DRY_RUN_CMD ${pkgs.git}/bin/git clone --branch master ${URL} ${REPO}
    else
      $DRY_RUN_CMD ${pkgs.git}/bin/git -C ${REPO} pull origin master
    fi
  '';

  home.activation.stowDotFiles = lib.hm.dag.entryAfter [ "setupDotfiles" "linkGeneration" ] ''
    set -euo pipefail
    cd ${REPO}
    $DRY_RUN_CMD ${pkgs.stow}/bin/stow --adopt --restow --verbose -t "$HOME" .
  '';

  home.packages = with pkgs; [
    stow
  ];
}
