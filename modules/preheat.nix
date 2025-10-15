{ config, pkgs, lib, ... }:
let 
	preheatTargets = [ 
	   "${pkgs.wezterm}/bin/wezterm"
	];
in {

   environment.systemPackages = [ pkgs.vmtouch ]:

   systemd.services.preheat = {
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

   systemd.timers.preheat = {
   	wantedBy = [ "timers.target" ];
	timerConfig = {
		OnBootSec = "30s";
		OnUnitActiveSec = "1h";
		Persistent = true;
	};
   };


}
