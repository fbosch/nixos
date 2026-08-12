{ inputs
, config
, lib
, ...
}:
let
  inherit (config) hosts;
  hostMetadataType =
    hostName:
    import ../../lib/host-metadata.nix {
      inherit lib hostName;
    };
  hostMetadata = lib.mapAttrs (_name: host: host.metadata) hosts;
  systems = lib.mapAttrs (_name: host: host.metadata.system) hosts;

  platformModules =
    name:
    if lib.hasSuffix "-darwin" systems.${name} then
      config.flake.modules.darwin
    else
      config.flake.modules.nixos;

  resolveModules =
    name: modules:
    let
      platform = platformModules name;
      homeManager = config.flake.modules.homeManager or { };
      resolve =
        module:
        if !builtins.isString module then
          module
        else if builtins.hasAttr module platform then
          platform.${module}
        else if builtins.hasAttr module homeManager then
          null
        else
          throw "Host `${name}` references unknown module aspect `${module}`";
    in
    lib.filter (module: module != null) (map resolve modules);

  resolveHomeManagerModules =
    modules:
    let
      homeManager = config.flake.modules.homeManager or { };
    in
    map (module: homeManager.${module}) (
      lib.unique (
        lib.filter (module: builtins.isString module && builtins.hasAttr module homeManager) modules
      )
    );

  mkConfiguration =
    name: host:
    let
      hostArgs = {
        hostMeta = host.metadata;
        hostKey = name;
      };
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
      specialArgs = hostArgs;
      modules = resolveModules name host.modules ++ [
        hostBuilder.homeManagerModule
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = hostArgs;
            sharedModules = resolveHomeManagerModules host.modules;
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
        lib.types.submodule (
          { name, ... }: {
            options = {
              metadata = lib.mkOption {
                type = hostMetadataType name;
                description = "Host metadata";
              };

              modules = lib.mkOption {
                type = lib.types.listOf lib.types.raw;
                description = ''
                  Module aspect names and raw platform modules. Named aspects load their
                  NixOS or nix-darwin module and, when present, their matching Home Manager module.
                '';
              };
            };
          }
        )
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
    # Host configuration flow:
    #
    #   ┌──────────────────────────────────────┐
    #   │ modules/hosts                        │
    #   │ hosts.<name>: metadata + modules     │
    #   └──────────────────┬───────────────────┘
    #                      │ hostSystem
    #                      v
    #              ┌────────────────┐
    #              │ systems.<name> │
    #              └───────┬────────┘
    #                      │
    #          ┌───────────┴───────────┐
    #          v                       v
    #   ┌─────────────┐         ┌─────────────┐
    #   │  *-linux    │         │  *-darwin   │
    #   └──────┬──────┘         └──────┬──────┘
    #          │                       │
    #          v                       v
    #   ┌─────────────────┐     ┌─────────────────┐
    #   │ nixosSystem     │     │ darwinSystem    │
    #   │ + NixOS HM      │     │ + Darwin HM     │
    #   │ + resolved mods │     │ + resolved mods │
    #   └────────┬────────┘     └────────┬────────┘
    #            │                       │
    #            v                       v
    #   nixosConfigurations      darwinConfigurations
    meta.hosts = hostMetadata;

    nixosConfigurations = lib.mapAttrs mkConfiguration (lib.filterAttrs isLinux hosts);
    darwinConfigurations = lib.mapAttrs mkConfiguration (lib.filterAttrs isDarwin hosts);
  };
}
