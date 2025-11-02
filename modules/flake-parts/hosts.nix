{ inputs, lib, config, ... }:

let
  prefix = "hosts/";
  collectHostsModules = modules: lib.filterAttrs (name: _: lib.hasPrefix prefix name) modules;
in
{
  flake.lib = {
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

    # Helper to load NixOS modules and Home Manager modules for a user
    # Three approaches:
    #
    # 1. Explicit (separate lists):
    #    mkHost {
    #      nixos = [ "system" "vpn" "fonts" ];
    #      homeManager = [ "users" "shell" "development" ];
    #      username = "fbb";
    #    }
    #
    # 2. Simple (single list, tries both namespaces):
    #    mkHost {
    #      modules = [ "system" "users" "flatpak" "desktop" "shell" ];
    #      username = "fbb";
    #    }
    #
    # 3. Preset-based:
    #    mkHost {
    #      preset = "desktop";  # or "server" or "devServer"
    #      username = "fbb";
    #    }
    #
    # Optional parameters:
    #   - hardware: List of hardware config paths
    #   - extraHomeManager: Extra home-manager imports (for external inputs)
    #   - extraNixos/extraHomeManager: Additional modules to add to preset
    mkHost = { 
      nixos ? [], 
      homeManager ? [], 
      modules ? [],
      preset ? null,
      hardware ? [],
      extraHomeManager ? [],
      extraNixos ? [],
      username 
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
        presetConfig = if preset != null 
          then config.flake.lib.presets.${preset} or (throw "Unknown preset: ${preset}")
          else { nixos = []; homeManager = []; };
        
        # If 'modules' is provided, use it for both namespaces
        # Otherwise use preset or explicit lists
        nixosModules = 
          if modules != [] then modules 
          else if preset != null then presetConfig.nixos ++ extraNixos
          else nixos;
        hmModules = 
          if modules != [] then modules 
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
                ++ (if preset != null then [] else extraHomeManager);
            }
          ];
      };
  };

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
                inputs.self.overlays.chromium-webapps-hardening
              ];
              
              home-manager.extraSpecialArgs = specialArgs;
            }
          ];
        };
      }
    ))
  ];
}
