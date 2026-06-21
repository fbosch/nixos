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
    system = "x86_64-linux";
    platform = {
      os = "linux";
      arch = "x86_64";
    };
    hardware = {
      vendor = "ASUSTeK COMPUTER INC.";
      model = "TUF Z370-PLUS GAMING";
      cpu = {
        vendor = "Intel";
        model = "Core i7-8700K";
        family = "Coffee Lake";
        cores = 6;
      };
      gpu = {
        vendor = "NVIDIA";
        model = "GeForce RTX 4070 Ti";
        kind = "discrete";
      };
    };
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
      { lib, ... }:
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
            "services/comfyui"

            # files
            "files/wakatime"
            "files/npmrc"

            # hardware
            "hardware/usb-automount"
            "hardware/fingerprint"
            "hardware/fancontrol"
            "hardware"

            # desktop features
            "gaming"
            "windows"

            # virtualization
            "virtualization/podman"

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
              # Flox cache: useful for prebuilt CUDA/NVIDIA-related artifacts.
              "https://cache.flox.dev"
              "https://comfyui.cachix.org"
              "https://nix-community.cachix.org"
              "https://cuda-maintainers.cachix.org"
              # CachyOS kernel cache (Hydra/Attic) for nix-cachyos-kernel artifacts.
              "https://attic.xuyh0120.win/lantian"
              # CachyOS kernel cache mirror built on Garnix.
              "https://cache.garnix.io"
            ];
            extra-trusted-public-keys = [
              "flox-cache-public-1:7F4OyH7ZCnFhcze3fJdfyXYLQw/aV7GEed86nQ7IsOs="
              "comfyui.cachix.org-1:33mf9VzoIjzVbp0zwj+fT51HG0y31ZTK3nzYZAX0rec="
              "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
              "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
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

        virtualisation.podman = {
          dockerCompat = lib.mkForce false;
          dockerSocket.enable = lib.mkForce false;
        };

        environment.sessionVariables = {
          TERMINAL = "wezterm";
          ELECTRON_OZONE_PLATFORM_HINT = "auto";
          TZ = ":/etc/localtime";
          TZDIR = "/etc/zoneinfo";
        };
      };
  };
}
