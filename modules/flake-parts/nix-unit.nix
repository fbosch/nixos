{ inputs, ... }:
{
  imports = [ inputs.nix-unit.modules.flake.default ];

  perSystem = _: {
    nix-unit = {
      inputs = {
        inherit (inputs) nixpkgs;
        inherit (inputs) flake-parts;
        inherit (inputs) nix-unit;
      };

      tests = { };
    };
  };
}
