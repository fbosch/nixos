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

        dotfilesActivation =
          let
            activationSource = builtins.readFile ../../modules/dotfiles.nix;
          in
          {
            testActivationNeverAdoptsDotfiles = {
              expr = lib.hasInfix "--adopt" activationSource;
              expected = false;
            };

            testActivationRestowsDotfiles = {
              expr = lib.hasInfix "--restow --verbose" activationSource;
              expected = true;
            };

            testExistingCheckoutIsNotReconciled = {
              expr = lib.any (command: lib.hasInfix command activationSource) [
                " fetch origin"
                " pull --ff-only"
                " reset --"
                " switch --"
              ];
              expected = false;
            };

            testPinnedRevisionIsBootstrapOnly = {
              expr = lib.hasInfix "DOTFILES_BOOTSTRAP_REV" activationSource;
              expected = true;
            };

            testBootstrapPublishesOnlyAfterCheckout = {
              expr = lib.hasInfix "mv \"$BOOTSTRAP_REPO\"" activationSource;
              expected = true;
            };

            testActivationValidatesCheckoutRoot = {
              expr = lib.hasInfix "rev-parse --show-toplevel" activationSource;
              expected = true;
            };

            testActivationUsesOneLifecycleEntry = {
              expr = lib.any (entry: lib.hasInfix entry activationSource) [
                "setupDotfiles"
                "stowDotFiles"
              ];
              expected = false;
            };

            testBootstrapDoesNotRewriteOrigin = {
              expr = lib.hasInfix "remote set-url" activationSource;
              expected = false;
            };
          };

        batActivation =
          let
            batSource = builtins.readFile ../../modules/shell/bat.nix;
          in
          {
            testCacheWaitsForDotfiles = {
              expr = lib.hasInfix "entryAfter [ \"dotfiles\" ]" batSource;
              expected = true;
            };

            testCacheDoesNotFollowAssetSymlinks = {
              expr = lib.hasInfix "find -L" batSource;
              expected = false;
            };
          };

        surgeService =
          let
            surgeSource = builtins.readFile ../../modules/applications/surge.nix;
          in
          {
            testExitWhenDoneDoesNotRestart = {
              expr = lib.hasInfix "Restart = if cfg.exitWhenDone then \"no\" else \"always\";" surgeSource;
              expected = true;
            };
          };

      };
    };
  };
}
