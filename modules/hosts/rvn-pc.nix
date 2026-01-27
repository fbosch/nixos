{ inputs
, config
, ...
}:
{
  # rvn-pc: Dendritic host configuration for desktop workstation
  # Hardware: Custom desktop with Intel CPU and NVIDIA GPU
  # Role: Primary workstation for gaming, development, and daily use

  flake = {
    # Host metadata
    meta.hosts.pc = {
      hostname = "rvn-pc";
      tailscale = "100.124.57.90";
      local = "192.168.1.169";
      sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA9bFB0RZWl7ofsEMEW4i8UJv448U/RT429+roe1gc9K";
    };

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
