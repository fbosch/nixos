{ config, inputs, ... }:
{
  imports = [ inputs.nix-unit.modules.flake.default ];

  perSystem = _: {
    nix-unit = {
      inherit inputs;

      tests = {
        sopsHelpers = import ../../tests/nix-unit/sops-helpers.nix {
          inherit (config.flake.lib) sopsHelpers;
        };

        portConflicts = import ../../tests/nix-unit/port-conflicts.nix {
          inherit (inputs.nixpkgs) lib;
        };
      };
    };
  };
}
