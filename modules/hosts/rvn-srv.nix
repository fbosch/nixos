{ inputs, config, ... }:

let
  hostResult = config.flake.lib.mkHost {
    preset = "server";
    modules = [
      "secrets"
      "nas"
      "services/home-assistant"
      "services/termix"
      "virtualization/podman"
      "system/scheduled-suspend"
    ];

    hostImports = [
      ../../machines/msi-cubi/configuration.nix
      ../../machines/msi-cubi/hardware-configuration.nix
      inputs.nixos-hardware.nixosModules.common-cpu-intel
      (
        { pkgs, ... }:
        {
          environment.systemPackages = [
            pkgs.xclip
            pkgs.xsel
          ];

          services.termix = {
            enable = true;
            port = 7310;
          };

          powerManagement.scheduledSuspend = {
            enable = true;
            schedules = {
              weekday = {
                suspendTime = "23:30";
                wakeTime = "05:30";
                days = "Mon,Tue,Wed,Thu,Fri";
              };
              weekend = {
                suspendTime = "02:00";
                wakeTime = "07:30";
                days = "Sat,Sun";
              };
            };
          };
        }
      )
    ];

    inherit (config.flake.meta.user) username;
  };
in
{
  flake.modules.nixos."hosts/rvn-srv" = hostResult._module;

  flake.hostConfigs.rvn-srv = hostResult._hostConfig;
}
