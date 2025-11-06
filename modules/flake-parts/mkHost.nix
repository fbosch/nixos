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
        else { nixos = [ ]; homeManager = [ ]; };
      nixosModules = if useCombined then modules else if preset != null then presetConfig.nixos ++ extraNixos else nixos;
      hmModules = if useCombined then modules else if preset != null then presetConfig.homeManager else homeManager;
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
