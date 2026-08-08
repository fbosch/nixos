{ inputs
, lib
, config
, ...
}:
let
  hostSystem = import ../../lib/host-system.nix { inherit lib; };
  prefix = "hosts/";

  isTopLevelHostModule =
    name:
    let
      hostPath = lib.removePrefix prefix name;
    in
    (lib.hasPrefix prefix name) && (!lib.hasInfix "/" hostPath);

  # Helper to build a host configuration (works for both NixOS and Darwin)
  mkHostConfig =
    hostType: name: hostModule:
    let
      hostId = lib.removePrefix prefix name;
      hostMeta = config.flake.lib.hostMeta hostId;

      validatedSystem = hostSystem {
        inherit (hostMeta) system;
        hostName = hostId;
        inherit hostType;
      };
      hostBuilder =
        {
          nixos = {
            builder = inputs.nixpkgs.lib.nixosSystem;
            homeManagerModule = inputs.home-manager.nixosModules.home-manager;
          };
          darwin = {
            builder = inputs.nix-darwin.lib.darwinSystem;
            homeManagerModule = inputs.home-manager.darwinModules.home-manager;
          };
        }.${hostType};
    in
    builtins.seq validatedSystem {
      name = hostId;
      value = hostBuilder.builder {
        inherit (hostMeta) system;
        specialArgs = { inherit hostMeta; };
        modules = [
          hostModule
          hostBuilder.homeManagerModule
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit hostMeta; };
            };
          }
        ];
      };
    };

  # Collect host modules from both namespaces
  nixosHostModules = lib.filterAttrs (name: _: isTopLevelHostModule name) config.flake.modules.nixos;
  darwinHostModules = lib.filterAttrs (name: _: isTopLevelHostModule name) (
    config.flake.modules.darwin or { }
  );
  nixosHostIds = builtins.map (lib.removePrefix prefix) (builtins.attrNames nixosHostModules);
  darwinHostIds = builtins.map (lib.removePrefix prefix) (builtins.attrNames darwinHostModules);
  discoveredHostIds = nixosHostIds ++ darwinHostIds;
  metadataHostNames = builtins.map (host: host.name) config.flake.meta.hosts;
  duplicateMetadataHostNames = builtins.attrNames (
    lib.filterAttrs (_: names: lib.length names > 1) (
      builtins.groupBy (host: host.name) config.flake.meta.hosts
    )
  );
  duplicatedModuleHostIds = lib.intersectLists nixosHostIds darwinHostIds;
  missingMetadataHostIds = lib.filter (name: !(lib.elem name metadataHostNames)) discoveredHostIds;
  metadataSystems = builtins.map
    (
      host:
      hostSystem {
        inherit (host) system;
        hostName = host.name;
      }
    )
    config.flake.meta.hosts;
  hostMetadataValidation =
    assert
    duplicateMetadataHostNames == [ ]
    || throw "Host metadata is duplicated for: ${lib.concatStringsSep ", " duplicateMetadataHostNames}";
    assert
    duplicatedModuleHostIds == [ ]
    || throw "Host modules are registered for both NixOS and Darwin: ${lib.concatStringsSep ", " duplicatedModuleHostIds}";
    assert
    missingMetadataHostIds == [ ]
    || throw "Host modules have no metadata: ${lib.concatStringsSep ", " missingMetadataHostIds}";
    builtins.deepSeq metadataSystems true;
in
{
  flake = {
    nixosConfigurations = builtins.seq hostMetadataValidation (
      lib.mapAttrs' (mkHostConfig "nixos") nixosHostModules
    );
    darwinConfigurations = builtins.seq hostMetadataValidation (
      lib.mapAttrs' (mkHostConfig "darwin") darwinHostModules
    );
  };
}
