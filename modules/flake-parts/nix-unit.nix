{ config, inputs, ... }:
{
  imports = [ inputs.nix-unit.modules.flake.default ];

  perSystem = _: {
    nix-unit = {
      inputs = {
        inherit (inputs) nixpkgs;
        inherit (inputs) flake-parts;
        inherit (inputs) nix-unit;
      };

      tests = import ../../tests/nix-unit/sops-helpers.nix {
        inherit (config.flake.lib) sopsHelpers;
      };
    };
  };
}
