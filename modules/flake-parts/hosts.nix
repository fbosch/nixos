{ inputs, lib, config, ... }:
let
  prefix = "hosts/";
  hostModules = lib.filterAttrs (name: _: lib.hasPrefix prefix name) config.flake.modules.nixos;
in
{
  flake = {
    nixosConfigurations = lib.mapAttrs'
      (name: module:
        let
          hostId = lib.removePrefix prefix name;
          specialArgs = {
            inherit inputs;
            inherit (config.flake) meta;
            system = "x86_64-linux";
            hostConfig = module // { name = hostId; };
          };
        in
        {
          name = hostId;
          value = inputs.nixpkgs.lib.nixosSystem {
            inherit specialArgs;
            modules = module.imports ++ [
              inputs.home-manager.nixosModules.home-manager
              { home-manager.extraSpecialArgs = specialArgs; }
            ];
          };
        }
      )
      hostModules;
  };
}
