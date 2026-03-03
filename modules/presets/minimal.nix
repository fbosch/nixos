{ config, ... }:
{
  flake.modules.nixos."presets/minimal" = {
    imports = config.flake.lib.resolve [
      "system"
      "users"
      "shell"
      "development"
    ];
  };

  flake.modules.homeManager."presets/minimal" = {
    imports = config.flake.lib.resolveHm [
      "users"
      "shell"
    ];
  };
}
