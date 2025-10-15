{ config, pkgs, lib, ... }
let 
	preheatTarget = [ 
	   "${pkgs.wezterm}/bin/wezterm"
	];
in {
	servcies.preload.enable = true;
	services.preload.extraConfig = ''
            model = 3
	    minsize = 200000
	'';

	environment.systemPackages = [ pkgs.vmtouch ];


}
