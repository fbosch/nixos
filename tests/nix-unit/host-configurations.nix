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
          _:
          {
            options.flake = {
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

  hostMeta =
    hosts: name:
    (import ../../modules/flake-parts/lib.nix {
      config.flake.meta.hosts = hosts;
      inherit lib;
    }).config.flake.lib.hostMeta name;

  declaration = system: {
    metadata = { inherit system; };
    modules = [ "example" ];
  };
in
{
  testPublishesHostMetadataByDeclarationKey = {
    expr = (collector { host = declaration "x86_64-linux"; }).meta.hosts;
    expected = {
      host = {
        system = "x86_64-linux";
      };
    };
  };

  testUsesDeclarationKeyAsHostIdentity = {
    expr =
      (normalizedHosts {
        host = {
          metadata = {
            role = "desktop";
            system = "x86_64-linux";
          };
          modules = [ ];
        };
      }).host.system;
    expected = "x86_64-linux";
  };

  testRejectsMetadataName = {
    expr =
      (builtins.tryEval (builtins.deepSeq
        (normalizedHosts {
          host = {
            metadata = {
              name = "conflicting-host";
              role = "desktop";
              system = "x86_64-linux";
            };
            modules = [ ];
          };
        })
        true)).success;
    expected = false;
  };

  testLooksUpHostMetadataByDeclarationKey = {
    expr = (hostMeta { host.system = "x86_64-linux"; } "host").system;
    expected = "x86_64-linux";
  };

  testRejectsUnknownHostMetadataKey = {
    expr = (builtins.tryEval (hostMeta { } "missing")).success;
    expected = false;
  };

  testBuildsNixOSHost = {
    expr = (collector { host = declaration "x86_64-linux"; }).nixosConfigurations.host;
    expected = {
      builder = "nixos";
      system = "x86_64-linux";
      specialArgs.hostMeta = {
        system = "x86_64-linux";
      };
      specialArgs.hostKey = "host";
      modules = [
        { _testMarker = "nixos"; }
        { _testMarker = "nixos-home-manager"; }
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs.hostMeta = {
              system = "x86_64-linux";
            };
            extraSpecialArgs.hostKey = "host";
          };
        }
      ];
    };
  };

  testBuildsDarwinHost = {
    expr = (collector { host = declaration "aarch64-darwin"; }).darwinConfigurations.host;
    expected = {
      builder = "darwin";
      system = "aarch64-darwin";
      specialArgs.hostMeta = {
        system = "aarch64-darwin";
      };
      specialArgs.hostKey = "host";
      modules = [
        { _testMarker = "darwin"; }
        { _testMarker = "darwin-home-manager"; }
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs.hostMeta = {
              system = "aarch64-darwin";
            };
            extraSpecialArgs.hostKey = "host";
          };
        }
      ];
    };
  };

  testRejectsUnsupportedSystems = {
    expr =
      (builtins.tryEval (
        builtins.attrNames (collector { host = declaration "x86_64-windows"; }).nixosConfigurations
      )).success;
    expected = false;
  };
}
