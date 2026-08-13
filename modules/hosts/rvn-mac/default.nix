{ config, ... }:
let
  hostMetadata = {
    role = "laptop";
    sshAlias = "mac";
    tailscale = "100.118.36.81";
    local = "192.168.167.54";
    sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKFeunJFBraRV+0gG6sjGxCu0iEPMvxvDlfAb7FxribY";
    primaryUser = config.flake.meta.user.username;
    useTailnet = true;
    system = "aarch64-darwin";
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
  hosts.rvn-mac = {
    metadata = hostMetadata;
    modules = [
      "presets/osx"
      "hosts/rvn-mac/platform"
      "hosts/rvn-mac/home"
      "users"
      "secrets"
    ]
    ++ [
      ({ hostKey, ... }: {
        networking.hostName = hostKey;
      })
    ];
  };
}
