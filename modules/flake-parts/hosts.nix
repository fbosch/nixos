{ inputs
, lib
, config
, ...
}:
let
  prefix = "hosts/";

  # Helper to build a host configuration (works for both NixOS and Darwin)
  mkHostConfig =
    hostType: name: hostModule:
    let
      hostId = lib.removePrefix prefix name;

      # Platform-specific defaults
      platformDefaults =
        {
          nixos = {
            defaultSystem = "x86_64-linux";
            builder = inputs.nixpkgs.lib.nixosSystem;
            homeManagerModule = inputs.home-manager.nixosModules.home-manager;
          };
          darwin = {
            defaultSystem = "aarch64-darwin";
            builder = inputs.nix-darwin.lib.darwinSystem;
            homeManagerModule = inputs.home-manager.darwinModules.home-manager;
          };
        }.${hostType};

      # Use the first system from config.systems that matches the platform type
      # For darwin hosts, prefer darwin systems; for nixos hosts, prefer linux systems
      evalSystem =
        if (config ? systems) && (config.systems != [ ]) then
          let
            isDarwinSystem = sys: lib.hasSuffix "-darwin" sys;
            matchingSystems = lib.filter (sys: (hostType == "darwin") == (isDarwinSystem sys)) config.systems;
          in
          if matchingSystems != [ ] then builtins.head matchingSystems else platformDefaults.defaultSystem
        else
          platformDefaults.defaultSystem;

      # Get host config from separate flake output (NixOS only for now)
      hostConfigData = config.flake.hostConfigs.${hostId} or { };

      hostConfigArgs =
        if hostType == "nixos" then
          {
            name = hostId;
          }
          // hostConfigData
        else
          { };
    in
    {
      name = hostId;
      value = platformDefaults.builder {
        system = evalSystem;
        modules = [
          {
            _module.args = {
              inherit inputs;
              hostConfig = hostConfigArgs;
            };
          }
          hostModule
          platformDefaults.homeManagerModule
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
            };
          }
        ];
      };
    };

  # Collect host modules from both namespaces
  nixosHostModules = lib.filterAttrs (name: _: lib.hasPrefix prefix name) config.flake.modules.nixos;
  darwinHostModules = lib.filterAttrs (name: _: lib.hasPrefix prefix name) (
    config.flake.modules.darwin or { }
  );
in
{
  flake = {
    nixosConfigurations = lib.mapAttrs' (mkHostConfig "nixos") nixosHostModules;
    darwinConfigurations = lib.mapAttrs' (mkHostConfig "darwin") darwinHostModules;
  };
}
