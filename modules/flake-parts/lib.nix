{ config, lib, ... }:
{
  options.flake.hostConfigs = lib.mkOption {
    type = lib.types.attrsOf lib.types.attrs;
    default = { };
    description = "Host-specific configuration metadata";
  };

  config.flake.lib = {
    # Icon override utilities (from lib/icon-overrides.nix)
    # Kept here because icon-overrides is tightly coupled to this flake's structure
    iconOverrides = import ../../lib/icon-overrides.nix;

    # Dendritic pattern helpers for module path resolution
    # These helpers allow using string paths in imports while maintaining dendritic pattern compliance

    # Resolve NixOS module paths
    # Usage: imports = config.flake.lib.resolve [ "presets/server" "secrets" ../../hardware.nix ];
    resolve = builtins.map (m: if builtins.isString m then config.flake.modules.nixos.${m} else m);

    # Resolve Home Manager module paths
    # Usage: home-manager.users.username.imports = config.flake.lib.resolveHm [ "users" "dotfiles" ];
    resolveHm = builtins.map (
      m: if builtins.isString m then config.flake.modules.homeManager.${m} else m
    );

    # Helper function to build host configurations from module lists
    # Handles preset expansion, Home Manager wiring, and module resolution
    mkHost =
      { nixos ? [ ]
      , homeManager ? [ ]
      , modules ? [ ]
      , preset ? null
      , hostImports ? [ ]
      , extraHomeManager ? [ ]
      , extraNixos ? [ ]
      , username
      , displayManagerMode ? config.flake.meta.displayManager.defaultMode
      ,
      }:
      let
        emptyPreset = {
          modules = [ ];
          nixos = [ ];
          homeManager = [ ];
        };
        presetConfig =
          if preset != null then
            config.flake.meta.presets.${preset} or (throw "Unknown preset: ${preset}")
          else
            emptyPreset;
        nixosModules = presetConfig.modules ++ presetConfig.nixos ++ modules ++ nixos ++ extraNixos;
        hmModules =
          presetConfig.modules ++ presetConfig.homeManager ++ modules ++ homeManager ++ extraHomeManager;
        resolveNixosModule = m: if builtins.isString m then (config.flake.modules.nixos.${m} or { }) else m;
        resolveHmModule =
          m: if builtins.isString m then (config.flake.modules.homeManager.${m} or { }) else m;
      in
      {
        # Store metadata separately to be accessed by hosts.nix
        _hostConfig = {
          inherit displayManagerMode;
        };

        # Return the module function
        _module = _: {
          imports =
            hostImports
            ++ (builtins.map resolveNixosModule nixosModules)
            ++ [
              {
                home-manager.users.${username}.imports = builtins.map resolveHmModule hmModules;
              }
            ];
        };
      };
  };
}
