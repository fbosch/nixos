{ config, ... }:
let
  hostMeta = {
    name = "rvn-mac-corp";
    role = "laptop";
    sshAlias = null;
    tailscale = null;
    local = null;
    sshPublicKey = null;
    useTailnet = false;
    corporate = true;
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

    modules.darwin."hosts/rvn-mac-corp" = {
      imports = config.flake.lib.resolveDarwin [
        "hosts/rvn-mac-corp/platform"
        "hosts/rvn-mac-corp/home"
        "hosts/rvn-mac-corp/aerospace"
        "hosts/rvn-mac-corp/cleanshot"

        # Darwin core system configuration (Cachix, nix settings, home-manager)
        "system"

        # Darwin-specific modules
        "fonts"
        "security"
        "homebrew"
      ];

      networking.hostName = hostMeta.name;
    };
  };
}
