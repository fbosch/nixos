{ config, system, pkgs, lib, inputs, ... }:

let
	REPO = lib.escapeShellArg "${config.home.homeDirectory}/dotfiles";
	URL = lib.escapeShellArg "https://github.com/fbosch/dotfiles";
	REV = lib.escapeShellArg inputs.dotfiles.rev;
in {
	imports = [ 
		inputs.zen-browser.homeModules.default
		inputs.flatpaks.homeManagerModules.nix-flatpak
		inputs.hyprshell.homeModules.hyprshell
		./modules/services.nix
		./modules/desktop.nix
		./modules/programs.nix
		./modules/flatpak.nix
	];

	home.username = "fbb";
	home.homeDirectory = "/home/fbb";
	home.stateVersion = "25.05";
	systemd.user.startServices = "sd-switch";

	home.packages = with pkgs; [ 
                hyprpaper
		hyprprop
		wezterm
		kitty
		rofi
		gtk4
		gtk4-layer-shell
		gnome-keyring
		gnome-tweaks
		gnomeExtensions.appindicator
		nautilus
		whitesur-gtk-theme
		loupe
		mako
		git-credential-manager
		stow
		pass
		delta
		ripgrep
		zoxide
		eza
		lf
		fish
		starship
		gnupg
		pinentry-curses
		steam
	        (pkgs.waybar.overrideAttrs (oldAttrs: {
	            mesonFlags = oldAttrs.mesonFlags ++ [ "-Dexperimental=true" ];
	        }))
	]; 


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
