{ inputs, config, ... }:

let
  hostResult = config.flake.lib.mkHost {
    preset = "server";

    hostImports = [
      ../../machines/msi-cubi/configuration.nix
      ../../machines/msi-cubi/hardware-configuration.nix
      inputs.nixos-hardware.nixosModules.common-cpu-intel
      (
        { pkgs, ... }:
        {
          environment.systemPackages = [
            pkgs.xclip
            pkgs.xsel
          ];

          services.termix.enable = true;
        }
      )
    ];

    modules = [
      "secrets"
      "nas"
      "services/home-assistant"
      "services/termix"
      "virtualization/podman"
    ];

    inherit (config.flake.meta.user) username;
  };
in
{
  flake.modules.nixos."hosts/rvn-srv" = hostResult._module;

  flake.hostConfigs.rvn-srv = hostResult._hostConfig;
}
