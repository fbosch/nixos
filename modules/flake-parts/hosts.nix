{ inputs, lib, config, ... }:
let
  prefix = "hosts/";
  hostModules = lib.filterAttrs (name: _: lib.hasPrefix prefix name) config.flake.modules.nixos;
in
{
  flake = {
    nixosConfigurations = lib.mapAttrs'
      (name: hostModule:
        let
          hostId = lib.removePrefix prefix name;
          evalSystem =
            if (config ? systems) && (config.systems != [ ])
            then builtins.head config.systems
            else "x86_64-linux";
          specialArgs = {
            inherit inputs;
            inherit (config.flake) meta;
            hostConfig = { name = hostId; };
          };
          hmSpecialArgs = specialArgs // { system = evalSystem; };
        in
        {
          name = hostId;
          value = inputs.nixpkgs.lib.nixosSystem {
            system = evalSystem;
            specialArgs = hmSpecialArgs;
            modules = [
              hostModule
              inputs.home-manager.nixosModules.home-manager
              { home-manager.extraSpecialArgs = hmSpecialArgs; }
            ];
          };
        }
      )
      hostModules;
  };
}
