{ inputs
, config
, ...
}:
{
  # rvn-srv: Dendritic host configuration for MSI Cubi server
  # Hardware: Intel-based mini PC
  # Role: Home server running Plex, Home Assistant, and container services

  flake = {
    # Host metadata
    meta.hosts.srv = {
      hostname = "rvn-srv";
      tailscale = "100.125.172.110";
      local = "192.168.1.46";
      sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJl/WCQsXEkE7em5A6d2Du2JAWngIPfA8sVuJP/9cuyq fbb@nixos";
    };

    modules.nixos."hosts/rvn-srv" =
      { pkgs, ... }:
      {
        imports = config.flake.lib.resolve [
          # Server preset (users, security, development, shell, system, vpn)
          "presets/server"

          # system
          "secrets"
          "nas"
          "system/scheduled-suspend"
          "system/ananicy"

          # services
          "services/home-assistant"
          "services/atticd"
          "services/attic-client"
          "services/komodo"
          "services/plex"
          "services/servarr"

          # containerized services
          "virtualization/podman"
          "services/containers/redlib"
          "services/containers/termix"

          # hardware configuration
          ../../machines/msi-cubi/configuration.nix
          ../../machines/msi-cubi/hardware-configuration.nix
          inputs.nixos-hardware.nixosModules.common-cpu-intel
        ];

        # Home Manager configuration for user
        home-manager.users.${config.flake.meta.user.username}.imports = config.flake.lib.resolveHm [
          # Server preset modules for Home Manager
          "users"
          "dotfiles"
          "security"
          "development"
          "shell"

          # Secrets for home-manager context
          "secrets"
        ];

        # Kernel tuning for server workload
        boot.kernel.sysctl = {
          "vm.swappiness" = 10; # Only swap when critically low on RAM
          "vm.vfs_cache_pressure" = 50; # Keep filesystem cache longer
          "vm.dirty_ratio" = 15; # Start sync at 15% RAM dirty
          "vm.dirty_background_ratio" = 10; # Background writes at 10%
        };

        # Scheduled suspend/wake for power savings
        powerManagement.scheduledSuspend = {
          enable = true;
          schedules = {
            weekday = {
              suspendTime = "00:30";
              wakeTime = "06:00";
              days = "Mon,Tue,Wed,Thu";
            };
            friday = {
              suspendTime = "02:00";
              wakeTime = "06:00";
              days = "Fri";
            };
            weekend = {
              suspendTime = "02:00";
              wakeTime = "08:00";
              days = "Sat,Sun";
            };
          };
        };

        # Clipboard utilities for remote X11 sessions
        environment.systemPackages = [
          pkgs.xclip
          pkgs.xsel
        ];

        # Service-specific configuration
        services = {
          ananicy.enable = true;
          plex.nginx.port = 32402;

          komodo = {
            core.host = "https://komodo.corvus-corax.synology.me";
            core.allowSignups = false;
            periphery.requirePasskey = false;
          };

          uptime-kuma = {
            enable = true;
            settings.HOST = "0.0.0.0";
          };
        };

        # Open port for uptime-kuma
        networking.firewall.allowedTCPPorts = [ 3001 ];

      };
  };
}
