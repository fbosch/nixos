{ inputs, config, ... }:
let
  hostMetadata = {
    role = "laptop";
    corporate = true;
    primaryUser = "Z6FBO";
    nixDistribution = "determinate";
    system = "aarch64-darwin";
    hardware = {
      vendor = "Apple";
      model = "MacBook Pro (2026)";
      memoryGiB = 48;
      cpu = {
        vendor = "Apple";
        model = "M5 Pro";
        family = "Apple Silicon";
      };
      gpu = {
        vendor = "Apple";
        model = "M5 Pro";
        kind = "integrated";
      };
    };
  };
in
{
  hosts.kmd-mac = {
    metadata = hostMetadata;
    modules = [
      inputs.determinate.darwinModules.default
      "hosts/kmd-mac/platform"
      "hosts/kmd-mac/home"
      "system"
      "development"
      "shell"
      "virtualization/podman"
      "aerospace"
      "alt-tab"
      "cleanshot"
      "fonts"
      "hazeover"
      "system-defaults"
      "security"
      "homebrew"
    ];
  };
}
