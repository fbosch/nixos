{ inputs
, config
, ...
}:
let
  hostMetadata = {
    role = "server";
    sshAlias = "srv";
    sshAgent = "gpg";
    tailscale = "100.125.172.110";
    local = "192.168.1.46";
    sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJl/WCQsXEkE7em5A6d2Du2JAWngIPfA8sVuJP/9cuyq fbb@nixos";
    useTailnet = false;
    dnsServers = [
      "127.0.0.1"
    ];
    system = "x86_64-linux";
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

  hosts.rvn-srv = {
    metadata = hostMetadata;
    modules = [
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

      # applications
      "applications/surge"

      # services
      "services/atuin"
      "services/home-assistant"
      "services/atticd"
      "services/attic"
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
      {
        services.surge.outputDir = "/mnt/nas/downloads";
      }
    ];
  };

  flake.nix = {
    settings = {
      max-jobs = "auto";
      cores = 0;
    };

    # De-prioritize Nix daemon scheduling so desktop workloads stay responsive.
    daemonCPUSchedPolicy = "batch";
    daemonIOSchedClass = "idle";
  };
}
