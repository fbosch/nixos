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

        # Networking configuration
        networking = {
          # Open port for uptime-kuma
          firewall.allowedTCPPorts = [ 3001 ];

          # Enable systemd-networkd for bonding support
          useNetworkd = true;
          useDHCP = false; # Disable legacy DHCP
        };

        systemd.network.enable = true;

        # NIC bonding configuration for dual ethernet ports
        # Using balance-rr (no switch config needed)
        systemd.network = {
          netdevs."10-bond0" = {
            netdevConfig = {
              Kind = "bond";
              Name = "bond0";
            };
            bondConfig = {
              Mode = "balance-rr"; # Round-robin (no switch config needed)
              TransmitHashPolicy = "layer3+4"; # Hash by IP+port
              MIIMonitorSec = "100ms"; # Link monitoring
            };
          };

          networks = {
            # Assign enp2s0 to bond
            "30-enp2s0" = {
              matchConfig.Name = "enp2s0";
              networkConfig.Bond = "bond0";
            };

            # Assign enp3s0 to bond
            "30-enp3s0" = {
              matchConfig.Name = "enp3s0";
              networkConfig.Bond = "bond0";
            };

            # Configure bond0 interface with static IP
            "40-bond0" = {
              matchConfig.Name = "bond0";
              linkConfig.RequiredForOnline = "carrier";
              networkConfig = {
                Address = "192.168.1.46/24";
                Gateway = "192.168.1.1";
                DNS = [
                  "192.168.1.202"
                  "192.168.1.2"
                  "45.90.28.240"
                  "45.90.30.240"
                ];
                LinkLocalAddressing = "no";
              };
            };
          };
        };
      };

  };
}
