{ config, inputs, ... }:
{
  imports = [ inputs.nix-unit.modules.flake.default ];

  perSystem = { lib, pkgs, ... }: {
    nix-unit = {
      inputs =
        (builtins.mapAttrs (_name: input: input.outPath) (builtins.removeAttrs inputs [ "self" ]))
        // {
          "hyprland/nixpkgs" = inputs.hyprland.inputs.nixpkgs.outPath;
          "nix-cachyos-kernel/nixpkgs" = inputs.nix-cachyos-kernel.inputs.nixpkgs.outPath;
        };

      tests = {
        iconOverrides = import ../../tests/nix-unit/icon-overrides.nix {
          inherit lib;
          composeIconTheme = config.flake.lib.iconOverrides.composeIconTheme pkgs;
        };

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

        hostConfigurations = import ../../tests/nix-unit/host-configurations.nix {
          inherit lib;
          inherit (config) hosts;
        };

        ownershipBoundaries = import ../../tests/nix-unit/ownership-boundaries.nix {
          inherit lib;
          darwinMachineContexts = {
            personal = {
              inherit (config.flake.darwinConfigurations.rvn-mac.config.environment) variables;
              inherit (config.flake.darwinConfigurations.rvn-mac.config.programs) fish;
            };
            corporate = {
              inherit (config.flake.darwinConfigurations.kmd-mac.config.environment) variables;
              inherit (config.flake.darwinConfigurations.kmd-mac.config.programs) fish;
            };
          };
          serverSshOwnership = {
            selectedOwner = config.flake.meta.hosts.rvn-srv.sshAgent;
            gpgSshSupport =
              config.flake.nixosConfigurations.rvn-srv.config.programs.gnupg.agent.enableSSHSupport;
            homeManagerSshAgent =
              config.flake.nixosConfigurations.rvn-srv.config.home-manager.users.${config.flake.meta.user.username}.services.ssh-agent.enable;
          };
        };

      };
    };

    checks.iconOverrides = import ../../tests/icon-overrides-check.nix {
      inherit lib pkgs;
      composeIconTheme = config.flake.lib.iconOverrides.composeIconTheme pkgs;
    };
  };
}
