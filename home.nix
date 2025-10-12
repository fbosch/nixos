{ config, pkgs, lib, zen-browser, dotfiles, dotfilesUrl, walker, ... }:
let
	REPO = lib.escapeShellArg "${config.home.homeDirectory}/dotfiles";
	URL = lib.escapeShellArg dotfilesUrl;
	REV = lib.escapeShellArg dotfiles.rev;
in {
	imports = [ 
		zen-browser.homeModules.twilight
		walker.homeManagerModules.default
	];

	home.username = "fbb";
	home.homeDirectory = "/home/fbb";
	home.stateVersion = "25.05";

	home.packages = with pkgs; [ 
		stow
		git-credential-manager
		pass
		delta
		ripgrep
		zoxide
		eza
		fd
		lf
		fish
		starship
		gnupg
		pinentry-curses
	]; 

	programs.bash.enable = true;
	programs.zen-browser.enable = true;
	programs.neovim.enable = true;
	programs.fzf.enable = true;
	programs.bat.enable = true;
	programs.gpg = {
		enable = true;
	};
	services.gpg-agent = {
		enable = true;
		pinentry.package = pkgs.pinentry-curses;
		enableSshSupport = true;
	};
	programs.walker = {
		enable = true;
		runAsService = true;
		
		config = {
			search.placeholder = "Search...";
			ui.fullscreen = false;
			list.height = 200;
		};
	};
	programs.git = { 
		enable = true;
		extraConfig.credential.helper = "manager";
		extraConfig.credential."https://github.com".username = "fbosch";
		extraConfig.credential.credentialStore = "gpg";
	};

	gtk = {
		enable = true;
		gtk3.extraConfig = {
			gtk-application-prefer-dark-theme = true;
		};
		gtk4.extraConfig = {
			gtk-application-prefer-dark-theme = true;
		};
	};

	home.activation.dotfilesClone = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
		set -euo pipefail
		if [ ! -d ${REPO}/.git ]; then
			$DRY_RUN_CMD ${pkgs.git}/bin/git clone ${URL} ${REPO}
		fi
		$DRY_RUN_CMD ${pkgs.git}/bin/git -C ${REPO} fetch origin
		$DRY_RUN_CMD ${pkgs.git}/bin/git -C ${REPO} checkout ${REV}
	'';

	home.activation.stowDotFiles = lib.hm.dag.entryAfter [ "dotfilesClone" "linkGeneration" ] ''
		set -euo pipefail
		cd ${REPO}
		$DRY_RUN_CMD ${pkgs.stow}/bin/stow --restow --verbose -t "$HOME" .
	'';
}
