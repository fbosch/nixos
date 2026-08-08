{ lib }:
let
  inputs = {
    nixpkgs.lib.nixosSystem = args: args;
    nix-darwin.lib.darwinSystem = args: args;
    home-manager = {
      nixosModules.home-manager = { };
      darwinModules.home-manager = { };
    };
  };

  loader =
    { metadataHosts ? [ ]
    , nixosHostIds ? [ ]
    , darwinHostIds ? [ ]
    ,
    }:
    import ../../modules/flake-parts/hosts.nix {
      inherit inputs lib;
      config.flake = {
        lib.hostMeta =
          name:
          lib.findFirst
            (
              host: host.name == name
            )
            (throw "Host metadata `${name}` is not defined")
            metadataHosts;
        meta.hosts = metadataHosts;
        modules = {
          nixos = lib.genAttrs (builtins.map (name: "hosts/${name}") nixosHostIds) (_: { });
          darwin = lib.genAttrs (builtins.map (name: "hosts/${name}") darwinHostIds) (_: { });
        };
      };
    };

  fails = args: (builtins.tryEval args).success;
in
{
  testNixOSBuilderUsesMetadataSystem = {
    expr =
      (loader {
        nixosHostIds = [ "host" ];
        metadataHosts = [
          {
            name = "host";
            system = "aarch64-linux";
          }
        ];
      }).flake.nixosConfigurations.host.system;
    expected = "aarch64-linux";
  };

  testDarwinBuilderUsesMetadataSystem = {
    expr =
      (loader {
        darwinHostIds = [ "host" ];
        metadataHosts = [
          {
            name = "host";
            system = "x86_64-darwin";
          }
        ];
      }).flake.darwinConfigurations.host.system;
    expected = "x86_64-darwin";
  };

  testDuplicateMetadataFails = {
    expr =
      fails
        (loader {
          nixosHostIds = [ "host" ];
          metadataHosts = [
            {
              name = "host";
              system = "x86_64-linux";
            }
            {
              name = "host";
              system = "x86_64-linux";
            }
          ];
        }).flake.nixosConfigurations;
    expected = false;
  };

  testDiscoveredHostWithoutMetadataFails = {
    expr = fails (loader { nixosHostIds = [ "host" ]; }).flake.nixosConfigurations;
    expected = false;
  };

  testDualNamespaceRegistrationFails = {
    expr =
      fails
        (loader {
          nixosHostIds = [ "host" ];
          darwinHostIds = [ "host" ];
          metadataHosts = [
            {
              name = "host";
              system = "x86_64-linux";
            }
          ];
        }).flake.nixosConfigurations;
    expected = false;
  };

  testMetadataOnlyHostIsAllowed = {
    expr =
      builtins.attrNames
        (loader {
          metadataHosts = [
            {
              name = "remote";
              system = "x86_64-linux";
            }
          ];
        }).flake.nixosConfigurations;
    expected = [ ];
  };

  testNixOSDarwinMismatchFails = {
    expr =
      fails
        (loader {
          nixosHostIds = [ "host" ];
          metadataHosts = [
            {
              name = "host";
              system = "aarch64-darwin";
            }
          ];
        }).flake.nixosConfigurations.host;
    expected = false;
  };
}
