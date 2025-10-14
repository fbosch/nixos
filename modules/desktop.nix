{ config, pkgs, lib, inputs, ... }:
{
	gtk = {
		enable = true;
		gtk3.enable = true;
		gtk3.extraConfig = {
			gtk-application-prefer-dark-theme = true;
		};
		gtk4.extraConfig = {
			gtk-application-prefer-dark-theme = true;
		};
	};

	dconf.enable = true;
	dconf.settings = {
		"org/gnome/shell/extensions/user-theme"  = {
name = "WhiteSure-Dark-Solid";
		};
	};
}
