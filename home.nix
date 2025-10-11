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
		git-credential-manager
	]; 
	programs.bash = {
		enable = true;
	};
	programs.zen-browser = {
		enable = true;
	};
	programs.git = { 
	        enable = true;
		extraConfig.credential.helper = "manager";
		extraConfig.credential."https://github.com".username = "fbosch";
		extraConfig.credential.credentialStore = "cache";
	};

	home.activation.dotfilesClone = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
		set -eu
		if [ ! -d ${REPO}/.git ]; then
			${pkgs.git}/bin/git clone ${URL} ${REPO} 
		fi
		${pkgs.git}/bin/git -C ${REPO} fetch --tags --force origin

	'';
		
		#${pkgs.git}/bin/git -C ${REPO} checkout origin master
	home.activation.stowDotFile = lib.hm.dag.entryAfter [ "dotfilesClone" ] ''
		set -eu
		cd "${repoDir}"
		${pkgs.git}/bin/git -C ${REPO} reset --hard HEAD
		${pkgs.stow}/bin/stow --adopt -vt "$HOME" */
	'';
}
