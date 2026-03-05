{ config, inputs, ... }:
{
  imports = [ inputs.nix-unit.modules.flake.default ];

  perSystem = _: {
    nix-unit = {
      inherit inputs;

      tests = import ../../tests/nix-unit/sops-helpers.nix {
        inherit (config.flake.lib) sopsHelpers;
      };
    };
  };
}
