{ config, inputs, ... }:
{
  flake.modules.nixos."presets/minimal" = {
    imports = config.flake.lib.resolve [
      "system"
      "users"
      "shell"
      "development"
    ];
  };

  flake.modules.homeManager."presets/minimal" = {
    imports = config.flake.lib.resolveHm [
      "users"
      "dotfiles"
      "shell"
      "development"
    ];
  };

  perSystem =
    { lib, system, ... }:
    let
      hostKey = "preset-minimal";
      mkHostMeta = targetSystem: {
        role = "server";
        system = targetSystem;
        corporate = false;
        sshAgent = "ssh-agent";
        useTailnet = false;
        nixDistribution = "upstream";
      };
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          inputs.self.overlays.default
          inputs.nix-bwrapper.overlays.default
        ];
      };
      nixosConfig = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit hostKey;
          hostMeta = mkHostMeta "x86_64-linux";
        };
        modules = [
          inputs.home-manager.nixosModules.home-manager
          config.flake.modules.nixos."presets/minimal"
          {
            boot.loader.grub.devices = [ "nodev" ];
            fileSystems."/" = {
              device = "none";
              fsType = "tmpfs";
            };
            system.stateVersion = "25.05";
          }
        ];
      };
      homeConfig = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = {
          inherit hostKey;
          hostMeta = mkHostMeta system;
        };
        modules = [ config.flake.modules.homeManager."presets/minimal" ];
      };
    in
    {
      nix-unit.tests.minimalPreset = lib.recursiveUpdate
        {
          testHomeManagerConfigurationEvaluates = {
            expr = lib.isDerivation homeConfig.activationPackage;
            expected = true;
          };
        }
        (lib.optionalAttrs (system == "x86_64-linux") {
          testNixosConfigurationEvaluates = {
            expr = lib.isDerivation nixosConfig.config.system.build.toplevel;
            expected = true;
          };
        });
    };
}
