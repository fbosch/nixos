{ config, ... }:
let
  hostMeta = {
    name = "rvn-mac";
    role = "laptop";
    sshAlias = "mac";
    tailscale = "100.118.36.81";
    local = "192.168.167.54";
    sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKFeunJFBraRV+0gG6sjGxCu0iEPMvxvDlfAb7FxribY";
    useTailnet = true;
    system = "aarch64-darwin";
    platform = {
      os = "darwin";
      arch = "arm64";
    };
    hardware = {
      vendor = "Apple";
      model = "MacBook Pro (2024)";
      memoryGiB = 24;
      cpu = {
        vendor = "Apple";
        model = "M4 Pro";
        family = "Apple Silicon";
        cores = 14;
      };
      gpu = {
        vendor = "Apple";
        model = "M4 Pro";
        kind = "integrated";
      };
    };
  };
in
{
  flake = {
    meta.hosts = [ hostMeta ];

    modules.darwin."hosts/rvn-mac" = {
      imports = config.flake.lib.resolveDarwin [
        "hosts/rvn-mac/platform"
        "hosts/rvn-mac/home"

        # Darwin core system configuration (Cachix, nix settings, home-manager)
        "system"

        # Darwin-specific modules
        "aerospace"
        "cleanshot"
        "fonts"
        "macos-defaults"
        "security"
        "secrets"
        "homebrew"
        "files/wakatime"
        "files/npmrc"
      ];

      networking.hostName = hostMeta.name;
    };
  };
}
