{ inputs
, config
, lib
, ...
}:
let
  inherit (config) hosts;
  hostSystem = import ../../lib/host-system.nix { inherit lib; };
  hostMetadata = lib.mapAttrsToList (name: host: host.metadata // { inherit name; }) hosts;
  systems = lib.mapAttrs
    (
      name: host:
        hostSystem {
          system = host.metadata.system;
          hostName = name;
        }
    )
    hosts;

  resolveModules =
    name:
    builtins.map (
      module:
      if builtins.isString module then
        (
          if lib.hasSuffix "-darwin" systems.${name} then
            config.flake.modules.darwin
          else
            config.flake.modules.nixos
        ).${module}
      else
        module
    );

  mkConfiguration =
    name: host:
    let
      hostMeta = config.flake.lib.hostMeta name;
      system = systems.${name};
      hostBuilder =
        if lib.hasSuffix "-darwin" system then
          {
            builder = inputs.nix-darwin.lib.darwinSystem;
            homeManagerModule = inputs.home-manager.darwinModules.home-manager;
          }
        else
          {
            builder = inputs.nixpkgs.lib.nixosSystem;
            homeManagerModule = inputs.home-manager.nixosModules.home-manager;
          };
    in
    hostBuilder.builder {
      inherit system;
      specialArgs = { inherit hostMeta; };
      modules = resolveModules name host.modules ++ [
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

  isLinux = name: _host: lib.hasSuffix "-linux" systems.${name};
  isDarwin = name: _host: lib.hasSuffix "-darwin" systems.${name};
in
{
  options = {
    hosts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            metadata = lib.mkOption {
              type = lib.types.attrs;
              description = "Host metadata without its name";
            };

            modules = lib.mkOption {
              type = lib.types.listOf lib.types.raw;
              description = "NixOS or nix-darwin module names and values";
            };
          };
        }
      );
      default = { };
      description = "Host declarations contributed by modules/hosts";
    };

    flake.darwinConfigurations = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.raw;
      default = { };
      description = "Instantiated nix-darwin host configurations";
    };
  };

  config.flake = {
    meta.hosts = hostMetadata;

    nixosConfigurations = lib.mapAttrs mkConfiguration (lib.filterAttrs isLinux hosts);
    darwinConfigurations = lib.mapAttrs mkConfiguration (lib.filterAttrs isDarwin hosts);
  };
}
