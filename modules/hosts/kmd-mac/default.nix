{ inputs, config, ... }:
let
  hostMeta = {
    name = "kmd-mac";
    role = "laptop";
    corporate = true;
    primaryUser = "Z6FBO";
    nixDistribution = "determinate";
    system = "aarch64-darwin";
    platform = {
      os = "darwin";
      arch = "arm64";
    };
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
  flake = {
    meta.hosts = [ hostMeta ];

    modules.darwin."hosts/kmd-mac" = {
      imports = [
        inputs.determinate.darwinModules.default
      ]
      ++ config.flake.lib.resolveDarwin [
        "hosts/kmd-mac/platform"
        "hosts/kmd-mac/home"
        "system"
        "aerospace"
        "cleanshot"
        "fonts"
        "macos-defaults"
        "security"
        "homebrew"
      ];

    };
  };
}
