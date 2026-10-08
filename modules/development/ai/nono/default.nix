let
  piProfile = builtins.fromJSON (builtins.readFile ./scripts/profile.json);
  systemConfiguration =
    { pkgs, ... }:
    {
      environment = {
        systemPackages = [ pkgs.nono ];
        etc."nono/pi.json".source = pkgs.writeText "pi-nono-profile.json" (
          builtins.toJSON piProfile
        );
      };
    };
in
{
  flake.modules = {
    nixos.development.imports = [ systemConfiguration ];
    darwin.development.imports = [ systemConfiguration ];
  };

  perSystem =
    { lib, pkgs, ... }:
    let
      evaluated = systemConfiguration { inherit pkgs; };
      profile = builtins.fromJSON evaluated.environment.etc."nono/pi.json".source.text;
    in
    {
      nix-unit.tests.nonoProfile = {
        testInstallsNono = {
          expr = map lib.getName evaluated.environment.systemPackages;
          expected = [ "nono" ];
        };
        testUsesSystemOwnedProfile = {
          expr = builtins.attrNames evaluated.environment.etc;
          expected = [ "nono/pi.json" ];
        };
        testKeepsDefaultAndRuntimeGroups = {
          expr = {
            inherit (profile) extends groups;
          };
          expected = {
            extends = "default";
            groups.include = [
              "node_runtime"
              "rust_runtime"
              "python_runtime"
              {
                name = "user_caches_macos";
                when = "macos";
              }
              {
                name = "user_caches_linux";
                when = "linux";
              }
              {
                name = "linux_sysfs_read";
                when = "linux";
              }
              "nix_runtime"
              "git_config"
              "unlink_protection"
            ];
          };
        };
        testPreservesExistingAccess = {
          expr = {
            inherit (profile) filesystem network workdir;
          };
          expected = {
            filesystem = {
              allow = [ "$HOME/.pi" ];
              read = [
                "$HOME/.agents/skills"
                "$HOME/.nvm"
              ];
              suppress_save_prompt = [ "/" ];
            };
            network.block = false;
            workdir.access = "readwrite";
          };
        };
        testKeepsSignalIsolationAndDisablesElevation = {
          expr = profile.security;
          expected = {
            signal_mode = "isolated";
            capability_elevation = false;
          };
        };
        testKeepsMacosLmdbSupport = {
          expr = profile.unsafe_macos_seatbelt_rules;
          expected = [ "(allow ipc-sysv-sem)" ];
        };
      };
    };
}
