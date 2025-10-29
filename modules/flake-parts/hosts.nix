{ inputs, lib, config, ... }:

let
  prefix = "hosts/";
  collectHostsModules = modules: lib.filterAttrs (name: _: lib.hasPrefix prefix name) modules;
in
{
  flake.nixosConfigurations = lib.pipe (collectHostsModules config.flake.modules.nixos) [
    (lib.mapAttrs' (
      name: module:
      let
        specialArgs = {
          inherit inputs;
          system = "x86_64-linux";
          hostConfig = module // {
            name = lib.removePrefix prefix name;
          };
        };
      in
      {
        name = lib.removePrefix prefix name;
        value = inputs.nixpkgs.lib.nixosSystem {
          inherit specialArgs;
          modules = module.imports ++ [
            inputs.home-manager.nixosModules.home-manager
            {
              nixpkgs.overlays = [
                inputs.self.overlays.default
                inputs.nix-webapps.overlays.lib
                inputs.nix-webapps.overlays.default
              ];
              
              home-manager.extraSpecialArgs = specialArgs;
              home-manager.useGlobalPkgs = true;
            }
          ];
        };
      }
    ))
  ];
}
