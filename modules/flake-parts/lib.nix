{ config, lib, ... }:
{
  config.flake.lib = {
    # Icon override utilities (from lib/icon-overrides.nix)
    # Kept here because icon-overrides is tightly coupled to this flake's structure
    iconOverrides = import ../../lib/icon-overrides.nix;

    # Dendritic pattern helpers for module path resolution
    # These helpers allow using string paths in imports while maintaining dendritic pattern compliance

    # Resolve NixOS module paths
    # Usage: imports = config.flake.lib.resolve [ "presets/server" "secrets" ../../hardware.nix ];
    resolve = builtins.map (m: if builtins.isString m then config.flake.modules.nixos.${m} else m);

    # Resolve Home Manager module paths
    # Usage: home-manager.users.username.imports = config.flake.lib.resolveHm [ "users" "dotfiles" ];
    resolveHm = builtins.map (
      m: if builtins.isString m then config.flake.modules.homeManager.${m} else m
    );

    # Resolve Darwin module paths
    # Usage: imports = config.flake.lib.resolveDarwin [ "security" "homebrew" ];
    resolveDarwin = builtins.map (
      m: if builtins.isString m then config.flake.modules.darwin.${m} else m
    );

    sopsHelpers =
      let
        rootOnly = {
          mode = "0400";
        };

        wheelReadable = {
          mode = "0440";
          group = "wheel";
        };

        worldReadable = {
          mode = "0444";
        };

        mkSecretsWithOpts =
          sopsFile: opts: names:
          builtins.listToAttrs (
            builtins.map
              (name: {
                inherit name;
                value = lib.recursiveUpdate { inherit sopsFile; } opts;
              })
              names
          );

        mkSecrets = sopsFile: mkSecretsWithOpts sopsFile { };

        mkSecret = sopsFile: opts: lib.recursiveUpdate { inherit sopsFile; } opts;
      in
      {
        inherit
          rootOnly
          wheelReadable
          worldReadable
          mkSecrets
          mkSecretsWithOpts
          mkSecret
          ;
      };
  };
}
