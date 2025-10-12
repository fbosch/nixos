{ config, system, pkgs, lib, inputs, dotfiles, dotfilesUrl, ... }:
let
	REPO = lib.escapeShellArg "${config.home.homeDirectory}/dotfiles";
	URL = lib.escapeShellArg "https://github.com/fbosch/dotfiles";
	REV = lib.escapeShellArg dotfiles.rev;
in {
	imports = [ 
		inputs.zen-browser.homeModules.twilight
		inputs.walker.homeManagerModules.default
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

	systemd.user.startServices = "sd-switch";

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
	programs.git = { 
		enable = true;
		extraConfig.credential.helper = "manager";
		extraConfig.credential."https://github.com".username = "fbosch";
		extraConfig.credential.credentialStore = "gpg";
	};

	programs.walker = {
		enable = true;
		runAsService = true;
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

	home.file."dotfiles" = {
		source = dotfiles;
		recursive = true;
	};

	home.activation.setupDotfilesGit = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
		set -euo pipefail
		if [ ! -d ${REPO}/.git ]; then
			$DRY_RUN_CMD ${pkgs.git}/bin/git -C ${REPO} init
			$DRY_RUN_CMD ${pkgs.git}/bin/git -C ${REPO} remote add origin ${URL}
		fi
	'';

	home.activation.stowDotFiles = lib.hm.dag.entryAfter [ "setupDotfilesGit" "linkGeneration" ] ''
		set -euo pipefail
		cd ${REPO}
		$DRY_RUN_CMD ${pkgs.stow}/bin/stow --restow --verbose -t "$HOME" .
	'';
}
