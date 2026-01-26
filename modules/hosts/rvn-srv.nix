{ inputs, config, ... }:

let
  hostResult = config.flake.lib.mkHost {
    preset = "server";
    modules = [
      "secrets"
      "nas"
      "system/scheduled-suspend"
      "system/ananicy"
      "services/home-assistant"
      "services/atticd"
      "services/attic-client"
      "services/komodo"
      "services/plex"
      "services/servarr"
      "virtualization/podman"
      "services/containers/redlib"
      "services/containers/termix"
    ];

    hostImports = [
      ../../machines/msi-cubi/configuration.nix
      ../../machines/msi-cubi/hardware-configuration.nix
      inputs.nixos-hardware.nixosModules.common-cpu-intel
      (
        { config
        , pkgs
        , lib
        , ...
        }:
        {
          boot.kernel.sysctl = {
            "vm.swappiness" = 10; # Only swap when critically low on RAM
            "vm.vfs_cache_pressure" = 50; # Keep filesystem cache longer
            "vm.dirty_ratio" = 15; # Start sync at 15% RAM dirty
            "vm.dirty_background_ratio" = 10; # Background writes at 10%
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

          environment.systemPackages = [
            pkgs.xclip
            pkgs.xsel
          ];

          services = {
            termix-container.port = 7310;

            plex = {
              enable = true;
              nginx.port = 32402;
            };

            komodo = {
              enable = true;
              core.host = "https://komodo.corvus-corax.synology.me";
              core.allowSignups = false;
              periphery.requirePasskey = false;
            };

            uptime-kuma = {
              enable = true;
              settings.HOST = "0.0.0.0";
            };
          };

          networking.firewall.allowedTCPPorts = [
            3001
          ];

          services.ananicy.enable = true;

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
