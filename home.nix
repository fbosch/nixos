{ config, pkgs, lib, zen-browser, dotfiles, dotfilesUrl, ... }:
let
	REPO = lib.escapeShellArg "${config.home.homeDirectory}/dotfiles";
	URL = lib.escapeShellArg dotfilesUrl;
	REV = lib.escapeShellArg dotfiles.rev;
in {
	imports = [ zen-browser.homeModules.twilight ];

	home.username = "fbb";
	home.homeDirectory = "/home/fbb";
	home.stateVersion = "25.05";

	home.packages = with pkgs; [ 
		stow 
		git
		git-credential-manager
	]; 

	programs.bash.enable = true;
	programs.zen-browser.enable = true;
	programs.git = { 
		enable = true;
		extraConfig.credential.helper = "manager";
		extraConfig.credential."https://github.com".username = "fbosch";
		extraConfig.credential.credentialStore = "cache";
	};

	home.activation.dotfilesClone = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
		set -euo pipefail
		if [ ! -d ${REPO}/.git ]; then
			$DRY_RUN_CMD ${pkgs.git}/bin/git clone ${URL} ${REPO}
		else
			$DRY_RUN_CMD ${pkgs.git}/bin/git -C ${REPO} fetch --tags --force origin
		fi
	'';

	home.activation.stowDotFiles = lib.hm.dag.entryAfter [ "dotfilesClone" "linkGeneration" ] ''
		set -euo pipefail
		
		$DRY_RUN_CMD ${pkgs.git}/bin/git -C ${REPO} reset --hard ${REV}
		cd ${REPO}
		$DRY_RUN_CMD ${pkgs.stow}/bin/stow --delete -vt "$HOME" */ 2>/dev/null || true
		$DRY_RUN_CMD ${pkgs.stow}/bin/stow --stow -vt "$HOME" */
	'';
}
