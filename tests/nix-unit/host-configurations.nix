{ lib }:
let
  inputs = {
    nixpkgs.lib.nixosSystem = args: args // { builder = "nixos"; };
    nix-darwin.lib.darwinSystem = args: args // { builder = "darwin"; };
    home-manager = {
      nixosModules.home-manager = {
        _testMarker = "nixos-home-manager";
      };
      darwinModules.home-manager = {
        _testMarker = "darwin-home-manager";
      };
    };
  };

  collector =
    hosts:
    (import ../../modules/flake-parts/host-configurations.nix {
      inherit inputs lib;
      config = rec {
        inherit hosts;
        flake = {
          lib = {
            hostMeta = name: hosts.${name}.metadata // { inherit name; };
          };
          modules = {
            nixos.example = {
              _testMarker = "nixos";
            };
            darwin.example = {
              _testMarker = "darwin";
            };
          };
        };
      };
    }).config.flake;

  normalizedHosts =
    hosts:
    (lib.evalModules {
      specialArgs = { inherit inputs; };
      modules = [
        ../../modules/flake-parts/meta
        ../../modules/flake-parts/host-configurations.nix
        (
          { config, ... }:
          {
            options.flake = {
              lib = lib.mkOption {
                type = lib.types.attrsOf lib.types.raw;
                default = { };
              };
              modules = lib.mkOption {
                type = lib.types.attrsOf lib.types.raw;
                default = { };
              };
              nixosConfigurations = lib.mkOption {
                type = lib.types.lazyAttrsOf lib.types.raw;
                default = { };
              };
            };

            config = {
              inherit hosts;
              flake = {
                lib.hostMeta = name: config.hosts.${name}.metadata;
                modules = {
                  nixos.example = { };
                  darwin.example = { };
                };
              };
            };
          }
        )
      ];
    }).config.flake.meta.hosts;

  declaration = name: system: {
    metadata = { inherit name system; };
    modules = [ "example" ];
  };
in
{
  testPublishesNormalizedHostMetadata = {
    expr = (collector { host = declaration "host" "x86_64-linux"; }).meta.hosts;
    expected = [
      {
        name = "host";
        system = "x86_64-linux";
      }
    ];
  };

  testInjectsMetadataNameFromDeclarationKey = {
    expr =
      (builtins.head (normalizedHosts {
        host = {
          metadata = {
            role = "desktop";
            system = "x86_64-linux";
          };
          modules = [ ];
        };
      })).name;
    expected = "host";
  };

  testBuildsNixOSHost = {
    expr = (collector { host = declaration "host" "x86_64-linux"; }).nixosConfigurations.host;
    expected = {
      builder = "nixos";
      system = "x86_64-linux";
      specialArgs.hostMeta = {
        name = "host";
        system = "x86_64-linux";
      };
      modules = [
        { _testMarker = "nixos"; }
        { _testMarker = "nixos-home-manager"; }
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs.hostMeta = {
              name = "host";
              system = "x86_64-linux";
            };
          };
        }
      ];
    };
  };

  testBuildsDarwinHost = {
    expr = (collector { host = declaration "host" "aarch64-darwin"; }).darwinConfigurations.host;
    expected = {
      builder = "darwin";
      system = "aarch64-darwin";
      specialArgs.hostMeta = {
        name = "host";
        system = "aarch64-darwin";
      };
      modules = [
        { _testMarker = "darwin"; }
        { _testMarker = "darwin-home-manager"; }
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs.hostMeta = {
              name = "host";
              system = "aarch64-darwin";
            };
          };
        }
      ];
    };
  };

  testRejectsUnsupportedSystems = {
    expr =
      (builtins.tryEval (
        builtins.attrNames (collector { host = declaration "host" "x86_64-windows"; }).nixosConfigurations
      )).success;
    expected = false;
  };
}
