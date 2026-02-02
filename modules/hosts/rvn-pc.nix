{ inputs
, config
, ...
}:
let
  hostMeta = {
    name = "rvn-pc";
    sshAlias = "pc";
    tailscale = "100.124.57.90";
    local = "192.168.1.169";
    sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA9bFB0RZWl7ofsEMEW4i8UJv448U/RT429+roe1gc9K";
    dnsServers = [
      "192.168.1.46"
      "192.168.1.2"
      "45.90.28.240"
      "45.90.30.240"
      "1.1.1.1"
      "1.0.0.1"
    ];
  };
in
{
  # rvn-pc: Dendritic host configuration for desktop workstation
  # Hardware: Custom desktop with Intel CPU and NVIDIA GPU
  # Role: Primary workstation for gaming, development, and daily use

  flake = {
    # Host metadata
    meta.hosts = [ hostMeta ];

    modules.nixos."hosts/rvn-pc" =
      { pkgs, ... }:
      {
        imports = config.flake.lib.resolve [
          # Desktop preset (users, security, development, shell, system, desktop environment)
          "presets/desktop"

          # system
          "secrets"
          "nas"
          "services/attic-client"

          # hardware
          "hardware/usb-automount"
          "hardware/storage"
          "hardware/fingerprint"
          "hardware/fancontrol"

          # desktop features
          "gaming"
          "windows"

          # virtualization
          "virtualization/docker"
          "virtualization/libvirt"

          # hardware configuration
          ../../machines/desktop/configuration.nix
          ../../machines/desktop/hardware-configuration.nix
          inputs.nixos-hardware.nixosModules.common-cpu-intel
          inputs.grub2-themes.nixosModules.default
        ];

        # Home Manager configuration for user
        home-manager.users.${config.flake.meta.user.username}.imports =
          config.flake.lib.resolveHm [
            # Desktop preset (includes users, dotfiles, fonts, security, desktop, applications, development, shell)
            "presets/desktop"

            # Shared modules with Home Manager components
            "secrets"
            "windows"
          ]
          ++ [
            # External Home Manager modules
            inputs.flatpaks.homeManagerModules.nix-flatpak
            inputs.vicinae.homeManagerModules.default

            # User directory configuration
            {
              xdg.userDirs = {
                enable = true;
                download = "/mnt/storage/Downloads";
              };
            }
          ];

        # Enable SSH for remote access
        services.openssh.enable = true;

        networking.nameservers = hostMeta.dnsServers;

        systemd.services.ethernet-watchdog = {
          description = "Ensure ethernet stays up";
          after = [ "NetworkManager.service" ];
          wants = [ "NetworkManager.service" ];
          serviceConfig = {
            Type = "oneshot";
          };
          script = ''
            set -euo pipefail
            iface="enp0s31f6"
            ${pkgs.networkmanager}/bin/nmcli -g GENERAL.STATE dev show "$iface" >/tmp/ethernet-watchdog.state 2>&1 || {
              echo "nmcli failed; unable to read state"
              exit 0
            }
            state=$(cat /tmp/ethernet-watchdog.state)
            if [ "$state" != "100" ]; then
              echo "state=$state; reconnecting $iface"
              ${pkgs.networkmanager}/bin/nmcli dev disconnect "$iface" || true
              ${pkgs.networkmanager}/bin/nmcli dev connect "$iface" || {
                echo "reconnect failed for $iface"
                exit 0
              }
              echo "reconnected $iface"
            fi
          '';
        };

        systemd.timers.ethernet-watchdog = {
          description = "Check ethernet link regularly";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "1min";
            OnUnitActiveSec = "2min";
            RandomizedDelaySec = "20s";
          };
        };

        # Desktop-specific packages
        environment.systemPackages = [
          pkgs.wlr-randr
        ];

        # NVIDIA-specific environment variables
        environment.sessionVariables = {
          LIBVA_DRIVER_NAME = "nvidia";
          NVD_BACKEND = "direct";
          TERMINAL = "wezterm";
          GBM_BACKEND = "nvidia_drm";
          __GLX_VENDOR_LIBRARY_NAME = "nvidia";
          ELECTRON_OZONE_PLATFORM_HINT = "auto";
          GTK_USE_PORTAL = "0";
        };
      };
  };
}
