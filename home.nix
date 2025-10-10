{ config, pkgs, lib, zen-browser, repoUrl, dotRev, ... }:
let
	repoDir = "${config.home.homeDirectory}/dotfiles";
	REPO = lib.escapeShellArg repoDir;
	URL = lib.escapeShellArg repoUrl;
in {
	imports = [ zen-browser.homeModules.twilight ];
	home.username = "fbb";
	home.homeDirectory = "/home/fbb";
	home.stateVersion = "25.05";
	home.packages = with pkgs; [ 
		stow 
		git
	]; 
	programs.bash = {
		enable = true;
	};
	programs.zen-browser = {
		enable = true;
	};

	home.activation.dotfilesClone = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
		set -eu
		if [ ! -d ${REPO}/.git ]; then
			${pkgs.git}/bin/git clone ${URL} ${REPO} 
		fi
		${pkgs.git}/bin/git -C ${REPO} fetch --tags --force origin

	'';

	home.activation.stowDotFile = lib.hm.dag.entryAfter [ "dotfilesClone" ] ''
		set -eu
		${pkgs.git}/bin/git -C ${REPO} checkout --detach ${dotRev}
		${pkgs.git}/bin/git -C ${REPO} reset --hard ${dotRev}
		cd "${repoDir}"
		${pkgs.stow}/bin/stow --adopt -vt "$HOME" */
	'';
}
