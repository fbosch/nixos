{ config, lib, ... }:
{
  options.flake.hostConfigs = lib.mkOption {
    type = lib.types.attrsOf lib.types.attrs;
    default = { };
    description = "Host-specific configuration metadata";
  };

  config.flake.lib.mkHost =
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
      presetConfig =
        if preset != null then
          config.flake.meta.presets.${preset} or (throw "Unknown preset: ${preset}")
        else
          {
            modules = [ ];
            nixos = [ ];
            homeManager = [ ];
          };
      nixosModules = presetConfig.modules ++ presetConfig.nixos ++ modules ++ nixos ++ extraNixos;
      hmModules =
        presetConfig.modules ++ presetConfig.homeManager ++ modules ++ homeManager ++ extraHomeManager;
    in
    {
      # Store metadata separately to be accessed by hosts.nix
      _hostConfig = {
        inherit displayManagerMode;
      };

      # Return the module function
      _module = _moduleArgs: {
        imports =
          hostImports
          ++ (builtins.map (m: config.flake.modules.nixos.${m} or { }) nixosModules)
          ++ [
            {
              home-manager.users.${username}.imports =
                builtins.map
                  (
                    m: if builtins.isString m then (config.flake.modules.homeManager.${m} or { }) else m
                  )
                  hmModules;
            }
          ];
      };
    };
}
