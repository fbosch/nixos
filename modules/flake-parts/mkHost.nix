{ config, ... }:
{
  flake.lib.mkHost =
    { nixos ? [ ]
    , homeManager ? [ ]
    , modules ? [ ]
    , preset ? null
    , hostImports ? [ ]
    , extraHomeManager ? [ ]
    , extraNixos ? [ ]
    , username
    }:
    let
      useCombined = modules != [ ];
      presetConfig =
        if preset != null
        then config.flake.meta.presets.${preset} or (throw "Unknown preset: ${preset}")
        else { modules = [ ]; nixos = [ ]; homeManager = [ ]; };
      # When using 'modules', include additional nixos-only modules from 'nixos' parameter
      # When using 'preset', combine preset.modules + preset.nixos + extraNixos
      nixosModules = if useCombined then modules ++ nixos else if preset != null then presetConfig.modules ++ presetConfig.nixos ++ extraNixos else nixos;
      # When using 'modules', include additional homeManager-only modules from 'homeManager' parameter
      # When using 'preset', combine preset.modules + preset.homeManager
      hmModules = if useCombined then modules ++ homeManager else if preset != null then presetConfig.modules ++ presetConfig.homeManager else homeManager;
    in
    {
      imports =
        hostImports
        ++ (builtins.map (m: config.flake.modules.nixos.${m} or { }) nixosModules)
        ++ [
          {
            home-manager.users.${username}.imports =
              (builtins.map (m: if builtins.isString m then (config.flake.modules.homeManager.${m} or { }) else m) hmModules)
              ++ extraHomeManager;
          }
        ];
    };
}
