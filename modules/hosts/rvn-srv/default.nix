{ inputs
, config
, ...
}:
let
  hostMeta = {
    name = "rvn-srv";
    role = "server";
    sshAlias = "srv";
    tailscale = "100.125.172.110";
    local = "192.168.1.46";
    sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJl/WCQsXEkE7em5A6d2Du2JAWngIPfA8sVuJP/9cuyq fbb@nixos";
    useTailnet = false;
    dnsServers = [
      "127.0.0.1"
    ];
    system = "x86_64-linux";
    platform = {
      os = "linux";
      arch = "x86_64";
    };
    hardware = {
      vendor = "MSI";
      model = "Cubi";
      cpu = {
        vendor = "Intel";
        model = "N200";
        family = "Alder Lake-N";
        cores = 4;
      };
      gpu = {
        vendor = "Intel";
        model = "Alder Lake-N UHD Graphics";
        kind = "integrated";
      };
    };
  };
in
{
  # rvn-srv: Dendritic host configuration for MSI Cubi server
  # Hardware: Intel-based mini PC
  # Role: Home server running Plex, Home Assistant, and container services

  flake = {
    meta.hosts = [ hostMeta ];

    modules.nixos."hosts/rvn-srv" =
      { ... }:
      {
        imports =
          config.flake.lib.resolve [
            "hosts/rvn-srv/hardware"
            "hosts/rvn-srv/boot"
            "hosts/rvn-srv/platform"
            "hosts/rvn-srv/home"

            # Server preset (users, security, development, shell, system, vpn)
            "presets/server"

            # system
            "secrets"
            "nas"
            "system/scheduled-suspend"
            "system/ananicy"

            # files
            "files/wakatime"

            # applications
            "applications/surge"

            # services
            "services/atuin"
            "services/home-assistant"
            "services/atticd"
            "services/attic-client"
            "services/plex"
            "services/servarr"
            "services/tinyproxy"
            "services/nextdns"
            "services/wakapi"
            "services/freshrss"

            # containerized services
            "virtualization/podman"
            "services/containers/dozzle"
            "services/containers/gluetun"
            "services/containers/termix"
            "services/containers/glance"
            "services/containers/pihole"
            "services/containers/helium"
            "services/containers/komodo"
            "services/containers/openmemory"
            "services/containers/linkwarden"
            "services/containers/rdtclient"
            "services/containers/flaresolverr"
            "services/containers/speedtest-tracker"
            "services/containers/onwatch"
            "services/containers/rsshub"
            "services/containers/priceghost"

            # validation
            "validation/container-port-conflicts"
          ]
          ++ [
            inputs.nixos-hardware.nixosModules.common-cpu-intel
          ];
      };

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
  };
}
