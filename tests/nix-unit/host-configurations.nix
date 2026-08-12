{ lib, hosts }:
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
            homeManager = {
              example = {
                _testMarker = "home-manager-example";
              };
              home-only = {
                _testMarker = "home-manager-only";
              };
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
        (_: {
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
        })
      ];
    }).config.flake.meta.hosts;

  declaration = system: {
    metadata = { inherit system; };
    modules = [ "example" ];
  };
  homeOnlyDeclaration = system: {
    metadata = { inherit system; };
    modules = [
      "example"
      "home-only"
    ];
  };
  rolePresets = [
    "presets/desktop"
    "presets/server"
  ];
  expectedPresetByRole = {
    desktop = "presets/desktop";
    server = "presets/server";
  };
  hasConsistentRolePreset =
    host:
    let
      expectedPreset = expectedPresetByRole.${host.metadata.role} or null;
      selectedRolePresets = lib.filter
        (
          module: builtins.isString module && lib.elem module rolePresets
        )
        host.modules;
    in
    lib.length selectedRolePresets <= 1
    && (expectedPreset == null || selectedRolePresets == [ expectedPreset ]);
  roleHost = role: modules: {
    metadata = { inherit role; };
    inherit modules;
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
      (builtins.tryEval (
        builtins.deepSeq
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
          true
      )).success;
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
            sharedModules = [
              { _testMarker = "home-manager-example"; }
            ];
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
            sharedModules = [
              { _testMarker = "home-manager-example"; }
            ];
          };
        }
      ];
    };
  };

  testAcceptsHomeManagerOnlyAspect = {
    expr = (collector { host = homeOnlyDeclaration "x86_64-linux"; }).nixosConfigurations.host.modules;
    expected = [
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
          sharedModules = [
            { _testMarker = "home-manager-example"; }
            { _testMarker = "home-manager-only"; }
          ];
        };
      }
    ];
  };

  testRejectsUnsupportedSystems = {
    expr =
      (builtins.tryEval (
        builtins.deepSeq
          (normalizedHosts {
            host = {
              metadata = {
                role = "desktop";
                system = "x86_64-windows";
              };
              modules = [ ];
            };
          })
          true
      )).success;
    expected = false;
  };

  testDeclaredHostsHaveConsistentRolePresets = {
    expr = lib.all hasConsistentRolePreset (lib.attrValues hosts);
    expected = true;
  };

  testDesktopRejectsServerPreset = {
    expr = hasConsistentRolePreset (roleHost "desktop" [ "presets/server" ]);
    expected = false;
  };

  testServerRejectsDesktopPreset = {
    expr = hasConsistentRolePreset (roleHost "server" [ "presets/desktop" ]);
    expected = false;
  };

  testVmMayUseDesktopPreset = {
    expr = hasConsistentRolePreset (roleHost "vm" [ "presets/desktop" ]);
    expected = true;
  };

  testVmRejectsMultipleRolePresets = {
    expr = hasConsistentRolePreset (
      roleHost "vm" [
        "presets/desktop"
        "presets/server"
      ]
    );
    expected = false;
  };

  testLaptopMayOmitPreset = {
    expr = hasConsistentRolePreset (roleHost "laptop" [ ]);
    expected = true;
  };
}
