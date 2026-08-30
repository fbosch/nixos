{ inputs
, config
, ...
}:
let
  hostMetadata = {
    role = "desktop";
    sshAlias = "pc";
    tailscale = "100.124.57.90";
    mullvadDeviceName = "Groovy Eagle";
    local = "192.168.1.169";
    sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJl/WCQsXEkE7em5A6d2Du2JAWngIPfA8sVuJP/9cuyq fbb@nixos";
    dnsServers = [
      "192.168.1.46"
      "192.168.1.202"
    ];
    system = "x86_64-linux";
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

  hosts.rvn-pc = {
    metadata = hostMetadata;
    modules = [
      "hosts/rvn-pc/hardware"
      "hosts/rvn-pc/boot"
      "hosts/rvn-pc/platform"
      "hosts/rvn-pc/storage"
      "hosts/rvn-pc/home"
      "hosts/rvn-pc/login"

      "hosts/rvn-pc/disko"
      "hosts/rvn-pc/preservation"

      # Desktop preset (users, security, development, shell, system, desktop environment)
      "presets/desktop"

      # system
      "secrets"
      "system/networkmanager"
      "nas"
      "services/attic"
      "services/comfyui"
      "services/nextdns"
      "applications/surge"
      "worktrunk"

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
      "virtualization/libvirt"
    ]
    ++ [
      inputs.nixos-hardware.nixosModules.common-cpu-intel
      inputs.grub2-themes.nixosModules.default
      {
        nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.pinned ];

        services.surge.outputDir = "/mnt/storage/Downloads";

        nix = {
          settings = {
            max-jobs = "auto";
            cores = 0;
            extra-substituters = [ "https://attic.xuyh0120.win/lantian" ];
            extra-trusted-public-keys = [
              "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
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

        environment.sessionVariables = {
          TERMINAL = "wezterm";
          ELECTRON_OZONE_PLATFORM_HINT = "auto";
          TZ = ":/etc/localtime";
          TZDIR = "/etc/zoneinfo";
        };
      }
    ];
  };
}
