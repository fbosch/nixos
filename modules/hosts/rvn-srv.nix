{ inputs, config, ... }:

let
  hostResult = config.flake.lib.mkHost {
    preset = "server";
    modules = [
      "secrets"
      "nas"
      "services/home-assistant"
      "services/atticd"
      "services/attic-client"
      "services/termix"
      "services/komodo"
      "services/plex"
      "services/servarr"
      "services/redlib"
      "virtualization/podman"
      "system/scheduled-suspend"
      "system/ananicy"
    ];

    hostImports = [
      ../../machines/msi-cubi/configuration.nix
      ../../machines/msi-cubi/hardware-configuration.nix
      inputs.nixos-hardware.nixosModules.common-cpu-intel
      (
        {
          config,
          pkgs,
          lib,
          ...
        }:
        {
          environment.systemPackages = [
            pkgs.xclip
            pkgs.xsel
          ];

          services = {
            termix = {
              enable = true;
              port = 7310;
            };

            komodo = {
              enable = true;
              core.host = "https://komodo.corvus-corax.synology.me";
              core.allowSignups = false;
              periphery.requirePasskey = false;
            };

            plex.enable = true;

            uptime-kuma = {
              enable = true;
              settings.HOST = "0.0.0.0";
            };
          };

          networking.firewall.allowedTCPPorts = [
            3001
          ];

          services.ananicy.enable = true;

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
