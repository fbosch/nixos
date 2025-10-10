{
  description = "NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
		dotfiles = { url = "github:fbosch/dotfiles"; flake = false; };
  };

  outputs = { self, nixpkgs, dotfiles, home-manager, zen-browser } @ inputs: 
    {
      nixosConfigurations = {
        virtualbox-vm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/virtualbox-vm/configuration.nix
            ./hosts/virtualbox-vm/hardware-configuration.nix
            
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.fbb = import ./home.nix;
              home-manager.extraSpecialArgs = {
                inherit zen-browser;
                repoUrl = "https://github.com/fbosch/dotfiles.git";
                dotRev = dotfiles.rev;
              };
            }
          ];
          specialArgs = {
            inputs = { inherit zen-browser; };
          };
        };
      };
    };
}
