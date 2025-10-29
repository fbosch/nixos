{ inputs, ... }:

{
  flake.nixosConfigurations.rvn-vm = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = {
      inherit inputs;
      system = "x86_64-linux";
    };
    modules = [
      ../../machines/virtualbox-vm/configuration.nix
      ../../machines/virtualbox-vm/hardware-configuration.nix
      inputs.home-manager.nixosModules.home-manager
      {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          backupFileExtension = "hm-backup";
          users.fbb = {
            imports = [
              inputs.self.modules.homeManager.base
            ];
          };
          extraSpecialArgs = {
            inherit inputs;
            system = "x86_64-linux";
            pkgs = import inputs.nixpkgs {
              system = "x86_64-linux";
              config.allowUnfree = true;
              overlays = [
                inputs.self.overlays.default
                inputs.nix-webapps.overlays.lib
                inputs.nix-webapps.overlays.default
              ];
            };
          };
        };
      }
    ];
  };
}