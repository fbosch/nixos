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
    sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJl/WCQsXEkE7em5A6d2Du2JAWngIPfA8sVuJP/9cuyq fbb@nixos";
    dnsServers = [
      "192.168.1.46"
      "192.168.1.2"
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

          # files
          "files/wakatime"
          "files/npmrc"

          # hardware
          "hardware/usb-automount"
          "hardware/storage"
          "hardware/fingerprint"
          "hardware/fancontrol"

          # desktop features
          "gaming"
          "windows"

          # virtualization
          "virtualization/podman"
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
            "applications/surge"

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

              services.surge = {
                autostart = true;
                settings = {
                  general.default_download_dir = "/mnt/storage/Downloads";
                  connections.proxy_url = "http://192.168.1.46:8889";
                };
              };

            }
          ];

        # Limit concurrent Nix builds to leave headroom for desktop use;
        # system76-scheduler handles per-process CPU priority dynamically
        nix.settings.max-jobs = 4;

        # Enable SSH for remote access
        services.openssh.enable = true;

        # Act as a peer relay so tailnet devices (e.g. MacBook) use this node
        # instead of Tailscale's DERP servers when direct connections fail
        services.tailscale.extraSetFlags = [ "--relay-server-port=40000" ];
        networking.firewall.allowedUDPPorts = [ 40000 ];

        security.apparmor = {
          enable = true;
          killUnconfinedConfinables = false;
        };

        networking.nameservers = hostMeta.dnsServers;

        time.hardwareClockInLocalTime = true;

        environment.sessionVariables = {
          TERMINAL = "wezterm";
          ELECTRON_OZONE_PLATFORM_HINT = "auto";
        };
      };
  };
}
