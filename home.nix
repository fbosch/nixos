{ config, system, pkgs, lib, inputs, ... }:

let
	REPO = lib.escapeShellArg "${config.home.homeDirectory}/dotfiles";
	URL = lib.escapeShellArg "https://github.com/fbosch/dotfiles";
	REV = lib.escapeShellArg inputs.dotfiles.rev;
in {
	imports = [ 
		inputs.zen-browser.homeModules.default
		inputs.walker.homeManagerModules.default
		inputs.flatpaks.homeManagerModules.nix-flatpak
		./modules/services.nix
		./modules/programs.nix
		./modules/flatpak.nix
	];

	home.username = "fbb";
	home.homeDirectory = "/home/fbb";
	home.stateVersion = "25.05";
	home.packages = with pkgs; [ 
		stow
		git-credential-manager
		pass
		delta
		loupe
		nautilus
		ripgrep
		zoxide
		eza
		fd
		lf
		fish
		starship
		gnupg
		pinentry-curses
		gnome-tweaks
		gnomeExtensions.appindicator
	]; 

	systemd.user.startServices = "sd-switch";

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
		source = inputs.dotfiles;
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
