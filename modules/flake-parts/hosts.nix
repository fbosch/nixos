{ inputs, lib, config, ... }:

let
  prefix = "hosts/";
  collectHostsModules = modules: lib.filterAttrs (name: _: lib.hasPrefix prefix name) modules;
in
{
  flake = {
    lib = {
      # Common module presets for different host types
      presets = {
        # Minimal server (no GUI)
        server = {
          nixos = [ "system" "users" "security" "shell" ];
          homeManager = [ "users" "dotfiles" "shell" "security" ];
        };

        # Workstation with full desktop
        desktop = {
          nixos = [ "system" "users" "vpn" "fonts" "flatpak" "security" "desktop" "development" "shell" ];
          homeManager = [ "users" "dotfiles" "fonts" "flatpak" "security" "desktop" "applications" "development" "shell" "services" ];
        };

        # Development server (headless but with dev tools)
        devServer = {
          nixos = [ "system" "users" "vpn" "security" "development" "shell" ];
          homeManager = [ "users" "dotfiles" "shell" "development" "security" ];
        };
      };
      # Optional parameters:
      #   - hardware: List of hardware config paths
      #   - extraHomeManager: Extra home-manager imports (for external inputs)
      #   - extraNixos/extraHomeManager: Additional modules to add to preset
      mkHost =
        { nixos ? [ ]
        , homeManager ? [ ]
        , modules ? [ ]
        , preset ? null
        , hardware ? [ ]
        , extraHomeManager ? [ ]
        , extraNixos ? [ ]
        , username
        }:
          assert builtins.isList nixos;
          assert builtins.isList homeManager;
          assert builtins.isList modules;
          assert builtins.isList hardware;
          assert builtins.isList extraHomeManager;
          assert builtins.isList extraNixos;
          assert builtins.isString username;
          let
            # Apply preset if specified
            presetConfig =
              if preset != null
              then config.flake.lib.presets.${preset} or (throw "Unknown preset: ${preset}")
              else { nixos = [ ]; homeManager = [ ]; };

            # If 'modules' is provided, use it for both namespaces
            # Otherwise use preset or explicit lists
            nixosModules =
              if modules != [ ] then modules
              else if preset != null then presetConfig.nixos ++ extraNixos
              else nixos;
            hmModules =
              if modules != [ ] then modules
              else if preset != null then presetConfig.homeManager ++ extraHomeManager
              else homeManager;
          in
          {
            imports =
              # Hardware configs
              hardware
              # NixOS modules
              ++ (builtins.map (module: config.flake.modules.nixos.${module} or { }) nixosModules)
              # Home Manager modules
              ++ [
                {
                  home-manager.users.${username}.imports =
                    (builtins.map (module: config.flake.modules.homeManager.${module} or { }) hmModules)
                    ++ (if preset != null then [ ] else extraHomeManager);
                }
              ];
          };
    };

    nixosConfigurations = lib.pipe (collectHostsModules config.flake.modules.nixos) [
      (lib.mapAttrs' (
        name: module:
          let
            specialArgs = {
              inherit inputs;
              inherit (config.flake) meta;
              system = "x86_64-linux";
              # Surface host info
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
                  home-manager.extraSpecialArgs = specialArgs;
                }
              ];
            };
          }
      ))
    ];
  };
}
