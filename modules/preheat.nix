{ config, pkgs, lib, ... }:
let 
	preheatTargets = [ 
	   "${pkgs.wezterm}/bin/wezterm"
	];
in {

   home.packages = [ pkgs.vmtouch ];

   services.preheat = {
	   description = "Preload selected binaries into cache";
	   after = [ "local-fs.target" ];
	   wantedBy = [ "multi-user.target" ];
	   serviceConfig = {
	      Type = "oneshot";
	      ExecStart = ''
	        ${pkgs.vmtouch}/bin/vmtouch -q -f -t -v -m 20% \
		   ${lib.concatStringsSep " " preheatTargets}
	      '';
	   };
   };

}
