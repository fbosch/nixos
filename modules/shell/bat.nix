{ inputs, ... }:
let
  systemPackages = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.glow ];
  };
  homeManagerBat =
    { config
    , pkgs
    , lib
    , ...
    }:
    {
      programs.bat.enable = true;

      home.activation.batCache = lib.mkForce (
        lib.hm.dag.entryAfter [ "dotfiles" ] ''
          set -euo pipefail

          export XDG_CACHE_HOME=${lib.escapeShellArg config.xdg.cacheHome}
          config_dir=${lib.escapeShellArg "${config.xdg.configHome}/bat"}
          cache_marker="$XDG_CACHE_HOME/home-manager/bat-cache-input"
          cache_input="$({
            printf '%s\0' ${lib.escapeShellArg (toString config.programs.bat.package)}
            for assets_dir in "$config_dir/themes" "$config_dir/syntaxes"; do
              if [ -d "$assets_dir" ]; then
                ${pkgs.findutils}/bin/find -P "$assets_dir" -type f -print0 \
                  | ${pkgs.coreutils}/bin/sort -z \
                  | while IFS= read -r -d "" asset; do
                    printf '%s\0' "$asset"
                    ${pkgs.coreutils}/bin/sha256sum "$asset"
                  done
              fi
            done
          } | ${pkgs.coreutils}/bin/sha256sum | ${pkgs.coreutils}/bin/cut -d ' ' -f 1)"

          if [ -r "$cache_marker" ] && [ "$(<"$cache_marker")" = "$cache_input" ]; then
            verboseEcho "Bat cache inputs unchanged, skipping rebuild"
          else
            mkdir -p "$(dirname "$cache_marker")"
            verboseEcho "Rebuilding bat theme cache"
            (
              cd ${pkgs.emptyDirectory}
              run ${lib.getExe config.programs.bat.package} cache --build
            )
            printf '%s\n' "$cache_input" > "$cache_marker"
          fi
        ''
      );
    };
in
{
  flake.modules = {
    nixos.shell = systemPackages;
    darwin.shell = systemPackages;
    homeManager.shell = homeManagerBat;
  };

  perSystem =
    { lib, pkgs, ... }:
    let
      batHomeConfig =
        (inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            homeManagerBat
            {
              home = {
                username = "tester";
                homeDirectory = "/home/tester";
                stateVersion = "25.05";
              };
            }
          ];
        }).config;
      batCache = batHomeConfig.home.activation.batCache;
    in
    {
      nix-unit.tests.batActivation = {
        testCacheWaitsForDotfiles = {
          expr = batCache.after;
          expected = [ "dotfiles" ];
        };
        testCacheUsesPhysicalAssetTraversal = {
          expr = lib.hasInfix "/bin/find -P" batCache.data;
          expected = true;
        };
      };
    };
}
