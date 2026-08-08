{ config, inputs, ... }:
{
  imports = [ inputs.nix-unit.modules.flake.default ];

  perSystem = { lib, ... }: {
    nix-unit = {
      inputs = builtins.mapAttrs (_name: input: input.outPath) (builtins.removeAttrs inputs [ "self" ]);

      tests = {
        sopsHelpers = import ../../tests/nix-unit/sops-helpers.nix {
          inherit (config.flake.lib) sopsHelpers;
        };

        portConflicts = import ../../tests/nix-unit/port-conflicts.nix {
          inherit (config.flake.lib) portConflicts;
        };

        startupPolicy = import ../../tests/nix-unit/startup-policy.nix {
          inherit (config.flake.lib) startupPolicy;
        };

        hostSystem = import ../../tests/nix-unit/host-system.nix {
          hostSystem = import ../../lib/host-system.nix { inherit lib; };
        };

        hostLoader = import ../../tests/nix-unit/host-loader.nix { inherit lib; };

        ownershipBoundaries = import ../../tests/nix-unit/ownership-boundaries.nix {
          inherit lib;
        };

      };
    };
  };
}
