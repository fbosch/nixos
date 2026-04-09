{ inputs
, config
, ...
}:
let
  hostMeta = {
    name = "rvn-pc";
    role = "desktop";
    sshAlias = "pc";
    tailscale = "100.124.57.90";
    local = "192.168.1.169";
    sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJl/WCQsXEkE7em5A6d2Du2JAWngIPfA8sVuJP/9cuyq fbb@nixos";
    dnsServers = [
      "192.168.1.46"
      "192.168.1.202"
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
      { ... }:
      {
        imports =
          config.flake.lib.resolve [
            "hosts/rvn-pc/hardware"
            "hosts/rvn-pc/boot"
            "hosts/rvn-pc/platform"
            "hosts/rvn-pc/storage"
            "hosts/rvn-pc/home"

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
            "hardware/fingerprint"
            "hardware/fancontrol"

            # desktop features
            "gaming"

            # virtualization
            "virtualization/podman"
            "virtualization/libvirt"

          ]
          ++ [
            inputs.nixos-hardware.nixosModules.common-cpu-intel
            inputs.grub2-themes.nixosModules.default
          ];

        # Keep rebuilds fast while reserving CPU headroom for desktop responsiveness.
        nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.default ];

        nix = {
          settings = {
            max-jobs = "auto";
            cores = 0;
            extra-substituters = [
              "https://cache.flox.dev"
              "https://attic.xuyh0120.win/lantian"
              "https://cache.garnix.io"
            ];
            extra-trusted-public-keys = [
              "flox-cache-public-1:7F4OyH7ZCnFhcze3fJdfyXYLQw/aV7GEed86nQ7IsOs="
              "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
              "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
            ];
          };

          # De-prioritize Nix daemon scheduling so desktop workloads stay responsive.
          daemonCPUSchedPolicy = "batch";
          daemonIOSchedClass = "idle";
        };

        security.apparmor = {
          enable = true;
          killUnconfinedConfinables = false;
        };

        time.hardwareClockInLocalTime = true;

        environment.sessionVariables = {
          TERMINAL = "wezterm";
          ELECTRON_OZONE_PLATFORM_HINT = "auto";
          TZ = ":/etc/localtime";
          TZDIR = "/etc/zoneinfo";
        };
      };
  };
}
